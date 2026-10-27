import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from agent_config import GENIE_DIR, load_agents, parse_benchmark_sql, render_value, validate_agent


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, capture_output=True, text=True)


def validate_command(selected_key: str | None) -> None:
    for agent in load_agents(selected_key):
        validate_agent(agent)
        print(f"PASS {agent['key']}")


def render_command(selected_key: str | None, catalog: str, gold_schema: str, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    for agent in load_agents(selected_key):
        rendered = render_value(validate_agent(agent), catalog, gold_schema)
        destination = output / agent["config"]
        destination.write_text(json.dumps(rendered, indent=2) + "\n")
        print(destination)


def check_sql_command(
    selected_key: str | None,
    profile: str,
    warehouse_id: str,
    catalog: str,
    gold_schema: str,
    output: Path | None,
) -> None:
    results: list[dict[str, Any]] = []
    for agent in load_agents(selected_key):
        config = validate_agent(agent)
        sql_items = [
            (f"example:{item['id']}", item["sql"][0])
            for item in config.get("instructions", {}).get("example_question_sqls", [])
        ]
        sql_items.extend(parse_benchmark_sql(GENIE_DIR / agent["benchmark_sql"]).items())
        for sql_id, template in sql_items:
            sql = render_value(template, catalog, gold_schema)
            completed = run_command([
                "databricks", "experimental", "aitools", "tools", "query",
                "--warehouse", warehouse_id, "--profile", profile, sql,
            ])
            passed = completed.returncode == 0
            print(f"{'PASS' if passed else 'FAIL'} {agent['key']} {sql_id}")
            results.append({
                "agent": agent["key"], "id": sql_id, "passed": passed,
                "stdout": completed.stdout, "stderr": completed.stderr,
            })
    if output:
        output.write_text(json.dumps(results, indent=2) + "\n")
    if any(not result["passed"] for result in results):
        raise SystemExit(1)


def list_spaces(profile: str) -> list[dict[str, Any]]:
    completed = run_command([
        "databricks", "genie", "list-spaces", "--page-size", "100", "-o", "json",
        "--profile", profile,
    ])
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip())
    payload = json.loads(completed.stdout)
    if isinstance(payload, list):
        return payload
    return payload.get("spaces", [])


def publish_command(
    agent_key: str,
    profile: str,
    warehouse_id: str,
    catalog: str,
    gold_schema: str,
    parent_path: str,
    approved: bool,
) -> None:
    if not approved:
        raise ValueError("Live publication requires --approve-live after configuration review")
    agent = load_agents(agent_key)[0]
    rendered = render_value(validate_agent(agent), catalog, gold_schema)
    matches = [space for space in list_spaces(profile) if space.get("title") == agent["title"]]
    if len(matches) > 1:
        raise ValueError(f"Multiple live spaces have title {agent['title']}")
    body = {
        "warehouse_id": warehouse_id,
        "title": agent["title"],
        "description": agent["description"],
        "parent_path": parent_path,
        "serialized_space": json.dumps(rendered, separators=(",", ":")),
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json") as request_file:
        json.dump(body, request_file)
        request_file.flush()
        if matches:
            space_id = matches[0].get("space_id") or matches[0].get("id")
            command = ["databricks", "genie", "update-space", space_id]
        else:
            mkdir = run_command([
                "databricks", "workspace", "mkdirs", parent_path, "--profile", profile,
            ])
            if mkdir.returncode != 0:
                raise RuntimeError(mkdir.stderr.strip())
            command = ["databricks", "genie", "create-space"]
        completed = run_command(
            command + ["--json", f"@{request_file.name}", "-o", "json", "--profile", profile]
        )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip())
    print(completed.stdout)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--agent")
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--agent")
    render_parser.add_argument("--catalog", required=True)
    render_parser.add_argument("--gold-schema", required=True)
    render_parser.add_argument("--output", type=Path, required=True)
    check_parser = subparsers.add_parser("check-sql")
    check_parser.add_argument("--agent")
    check_parser.add_argument("--profile", required=True)
    check_parser.add_argument("--warehouse-id", required=True)
    check_parser.add_argument("--catalog", required=True)
    check_parser.add_argument("--gold-schema", required=True)
    check_parser.add_argument("--output", type=Path)
    publish_parser = subparsers.add_parser("publish")
    publish_parser.add_argument("agent")
    publish_parser.add_argument("--profile", required=True)
    publish_parser.add_argument("--warehouse-id", required=True)
    publish_parser.add_argument("--catalog", required=True)
    publish_parser.add_argument("--gold-schema", required=True)
    publish_parser.add_argument("--parent-path", required=True)
    publish_parser.add_argument("--approve-live", action="store_true")
    return parser


def main() -> None:
    arguments = build_parser().parse_args()
    if arguments.command == "validate":
        validate_command(arguments.agent)
    elif arguments.command == "render":
        render_command(arguments.agent, arguments.catalog, arguments.gold_schema, arguments.output)
    elif arguments.command == "check-sql":
        check_sql_command(
            arguments.agent, arguments.profile, arguments.warehouse_id,
            arguments.catalog, arguments.gold_schema, arguments.output,
        )
    else:
        publish_command(
            arguments.agent, arguments.profile, arguments.warehouse_id,
            arguments.catalog, arguments.gold_schema, arguments.parent_path,
            arguments.approve_live,
        )


if __name__ == "__main__":
    main()
