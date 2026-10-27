import json
import re
from pathlib import Path
from typing import Any


GENIE_DIR = Path(__file__).resolve().parent
ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
BENCHMARK_PATTERN = re.compile(
    r"^-- benchmark: ([0-9a-f]{32})\n(.*?)(?=^-- benchmark: |\Z)",
    re.MULTILINE | re.DOTALL,
)
MUTATING_SQL_PATTERN = re.compile(
    r"\b(CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|MERGE|COPY|TRUNCATE|GRANT|REVOKE)\b",
    re.IGNORECASE,
)


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def load_agents(selected_key: str | None = None) -> list[dict[str, Any]]:
    agents = load_json(GENIE_DIR / "agents.json")["agents"]
    if selected_key is None:
        return agents
    selected = [agent for agent in agents if agent["key"] == selected_key]
    if not selected:
        raise ValueError(f"Unknown agent key: {selected_key}")
    return selected


def render_value(value: Any, catalog: str, gold_schema: str) -> Any:
    if isinstance(value, str):
        return value.replace("${catalog}", catalog).replace("${gold_schema}", gold_schema)
    if isinstance(value, list):
        return [render_value(item, catalog, gold_schema) for item in value]
    if isinstance(value, dict):
        return {key: render_value(item, catalog, gold_schema) for key, item in value.items()}
    return value


def validate_read_only_sql(sql: str, label: str) -> None:
    normalized = sql.strip().removesuffix(";").strip()
    if not re.match(r"^(SELECT|WITH|SHOW|DESCRIBE|EXPLAIN)\b", normalized, re.IGNORECASE):
        raise ValueError(f"{label} is not bounded read-only SQL")
    if MUTATING_SQL_PATTERN.search(normalized):
        raise ValueError(f"{label} contains a mutating SQL keyword")
    if ";" in normalized:
        raise ValueError(f"{label} contains multiple SQL statements")


def parse_benchmark_sql(path: Path) -> dict[str, str]:
    statements = {
        benchmark_id: sql.strip().removesuffix(";").strip()
        for benchmark_id, sql in BENCHMARK_PATTERN.findall(path.read_text())
    }
    for benchmark_id, sql in statements.items():
        validate_read_only_sql(sql, f"{path.name}:{benchmark_id}")
    return statements


def validate_sorted_ids(items: list[dict[str, Any]], label: str) -> list[str]:
    identifiers = [item["id"] for item in items]
    if identifiers != sorted(identifiers):
        raise ValueError(f"{label} must be sorted by id")
    if any(not ID_PATTERN.fullmatch(identifier) for identifier in identifiers):
        raise ValueError(f"{label} contains an invalid id")
    return identifiers


def validate_sources(config: dict[str, Any], agent_key: str) -> None:
    sources = config.get("data_sources", {})
    metric_views = sources.get("metric_views", [])
    if not metric_views:
        raise ValueError(f"{agent_key} must use metric views as primary sources")
    for source_type, entries in sources.items():
        identifiers = [entry["identifier"] for entry in entries]
        if identifiers != sorted(identifiers):
            raise ValueError(f"{agent_key} {source_type} must be sorted by identifier")
        for entry in entries:
            if not entry["identifier"].startswith("${catalog}.${gold_schema}."):
                raise ValueError(f"{agent_key} has an unparameterized source")
            columns = entry.get("column_configs", [])
            names = [column["column_name"] for column in columns]
            if names != sorted(names):
                raise ValueError(f"{agent_key} column_configs must be sorted")
    if any(not entry["identifier"].split(".")[-1].startswith("mv_") for entry in metric_views):
        raise ValueError(f"{agent_key} metric_views contains a non-metric source")


def validate_agent(agent: dict[str, Any]) -> dict[str, Any]:
    config = load_json(GENIE_DIR / agent["config"])
    if config.get("version") != 2:
        raise ValueError(f"{agent['key']} must use serialized-space version 2")
    validate_sources(config, agent["key"])
    sample_questions = config.get("config", {}).get("sample_questions", [])
    benchmarks = config.get("benchmarks", {}).get("questions", [])
    sample_ids = validate_sorted_ids(sample_questions, f"{agent['key']} sample questions")
    benchmark_ids = validate_sorted_ids(benchmarks, f"{agent['key']} benchmarks")
    if len(benchmarks) != 10:
        raise ValueError(f"{agent['key']} must contain 10 initial benchmarks")
    if set(sample_ids) & set(benchmark_ids):
        raise ValueError(f"{agent['key']} reuses a question id")
    for benchmark in benchmarks:
        if benchmark.get("answer") != [{"format": "SQL", "content": []}]:
            raise ValueError(f"{agent['key']} Agent-mode benchmarks must use empty SQL answers")
        if not benchmark.get("evaluation_note"):
            raise ValueError(f"{agent['key']} Agent-mode benchmark lacks evaluation criteria")
    instructions = config.get("instructions", {})
    instruction_ids: list[str] = []
    for key in ("example_question_sqls", "text_instructions", "join_specs"):
        instruction_ids.extend(
            validate_sorted_ids(instructions.get(key, []), f"{agent['key']} {key}")
        )
    if len(instruction_ids) != len(set(instruction_ids)):
        raise ValueError(f"{agent['key']} reuses an instruction id")
    for example in instructions.get("example_question_sqls", []):
        for sql in example["sql"]:
            validate_read_only_sql(sql, f"{agent['key']} example {example['id']}")
    benchmark_sql = parse_benchmark_sql(GENIE_DIR / agent["benchmark_sql"])
    if set(benchmark_sql) != set(benchmark_ids):
        raise ValueError(f"{agent['key']} benchmark SQL ids do not match its config")
    return config
