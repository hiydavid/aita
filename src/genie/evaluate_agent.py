import argparse
import json
from pathlib import Path
from typing import Any

from databricks.sdk import WorkspaceClient
from openai import OpenAI

from agent_config import load_agents, validate_agent



def load_benchmarks(agent_key: str) -> list[dict[str, Any]]:
    agent = load_agents(agent_key)[0]
    return validate_agent(agent)["benchmarks"]["questions"]


def extract_sql(item: Any) -> str | None:
    if getattr(item, "type", None) != "function_call":
        return None
    arguments = getattr(item, "arguments", "{}")
    if isinstance(arguments, str):
        arguments = json.loads(arguments)
    return arguments.get("sql")


def extract_message(item: Any) -> str | None:
    if getattr(item, "type", None) != "message":
        return None
    content = getattr(item, "content", [])
    texts = [getattr(part, "text", None) for part in content]
    return "\n".join(text for text in texts if text)


def evaluate(
    agent_key: str,
    space_id: str,
    profile: str,
    output: Path,
    limit: int | None,
    benchmark_ids: list[str] | None,
) -> None:
    workspace = WorkspaceClient(profile=profile)
    host = workspace.config.host
    if not host.startswith("http"):
        host = f"https://{host}"
    authorization = workspace.config.authenticate()["Authorization"]
    token = authorization.removeprefix("Bearer ")
    client = OpenAI(api_key=token, base_url=f"{host}/api/2.0/genie/agents/{space_id}")
    results: list[dict[str, Any]] = []
    benchmarks = load_benchmarks(agent_key)
    if benchmark_ids:
        benchmarks = [benchmark for benchmark in benchmarks if benchmark["id"] in benchmark_ids]
        if len(benchmarks) != len(set(benchmark_ids)):
            raise ValueError("One or more benchmark ids were not found")
    if limit is not None:
        benchmarks = benchmarks[:limit]
    for benchmark in benchmarks:
        sql_queries: list[str] = []
        final_response = ""
        error = None
        try:
            stream = client.responses.create(
                model="genie-agent",
                input=[{
                    "type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": benchmark["question"][0]}],
                }],
                stream=True,
            )
            for event in stream:
                if event.type == "response.output_item.done":
                    sql = extract_sql(event.item)
                    if sql:
                        sql_queries.append(sql)
                elif event.type == "response.completed":
                    messages = [extract_message(item) for item in event.response.output]
                    final_response = "\n".join(message for message in messages if message)
                elif event.type == "response.failed":
                    error = str(event.response.error)
        except Exception as exception:
            error = str(exception)
        status = "complete" if final_response and not error else "failed"
        print(f"{status.upper()} {benchmark['id']}")
        results.append({
            "id": benchmark["id"],
            "question": benchmark["question"][0],
            "evaluation_note": benchmark["evaluation_note"],
            "status": status,
            "executed_sql": sql_queries,
            "response": final_response,
            "error": error,
            "review": {"passed": None, "notes": ""},
        })
        output.write_text(json.dumps(results, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("agent")
    parser.add_argument("--space-id", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--benchmark-id", action="append", dest="benchmark_ids")
    arguments = parser.parse_args()
    evaluate(
        arguments.agent, arguments.space_id, arguments.profile, arguments.output,
        arguments.limit, arguments.benchmark_ids,
    )


if __name__ == "__main__":
    main()
