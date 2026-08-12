#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Ensure sibling modules import correctly when invoked via absolute path.
sys.path.insert(0, str(Path(__file__).parent))

from _builder import AgentInvocation  # noqa: E402
from _constants import DEFAULT_TIMEOUT_MS, SUPPORTED_CLIS_HELP  # noqa: E402
from _executor import execute_agent  # noqa: E402
from _loader import get_agents_dir, list_agents, load_agent  # noqa: E402
from _resolver import resolve_cli  # noqa: E402


_PERMISSION_RANK = {"read-only": 0, "safe-edit": 1, "yolo": 2}


def _compose_role_context(
    agents_dir: str, role_names: list[str]
) -> tuple[str | None, str, str, str | None, str | None]:
    """Load and compose zero or more role descriptors.

    An empty role selection is valid and launches without a role overlay. The
    most restrictive selected permission is used so composition cannot silently
    escalate authority.
    """
    if not role_names:
        return None, "", "safe-edit", None, None

    role_contexts: list[str] = []
    configured_clis: set[str] = set()
    permissions: list[str] = []
    models: set[str] = set()
    efforts: set[str] = set()

    for role_name in role_names:
        run_agent_cli, system_context, _, _, permission, model, effort = load_agent(
            agents_dir, role_name
        )
        role_contexts.append(f"## Selected role: {role_name}\n{system_context}")
        if run_agent_cli:
            configured_clis.add(run_agent_cli)
        permissions.append(permission)
        if model:
            models.add(model)
        if effort:
            efforts.add(effort)

    if len(configured_clis) > 1:
        names = ", ".join(sorted(configured_clis))
        raise ValueError(
            f"Selected roles require conflicting CLI backends ({names}). "
            "Select compatible roles or provide an explicit --cli override."
        )
    if len(models) > 1:
        raise ValueError(
            "Selected roles require conflicting models. Select compatible roles "
            "or remove model overrides from the role descriptors."
        )
    if len(efforts) > 1:
        raise ValueError(
            "Selected roles require conflicting reasoning efforts. Select "
            "compatible roles or remove effort overrides from the descriptors."
        )

    permission = min(permissions, key=lambda value: _PERMISSION_RANK[value])
    run_agent_cli = next(iter(configured_clis), None)
    model = next(iter(models), None)
    effort = next(iter(efforts), None)
    return (
        run_agent_cli,
        "\n\n".join(role_contexts),
        permission,
        model,
        effort,
    )


def _print_error(error: str, exit_code: int = 1, cli: str | None = None) -> None:
    payload = {"result": "", "exit_code": exit_code, "status": "error", "error": error}
    if cli is not None:
        payload["cli"] = cli
    print(json.dumps(payload))


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute external CLI AIs as sub-agents")
    parser.add_argument("--list", action="store_true", help="List available agents")
    parser.add_argument(
        "--agent",
        action="append",
        dest="agent_names",
        help="Role definition name; repeat for compatible role composition",
    )
    parser.add_argument("--prompt", help="Task prompt")
    parser.add_argument("--cwd", help="Working directory (absolute path)")
    parser.add_argument("--agents-dir", help="Directory containing agent definitions")
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_MS,
        help=f"Timeout in ms (default: {DEFAULT_TIMEOUT_MS})",
    )
    parser.add_argument("--cli", help=f"Force specific CLI ({SUPPORTED_CLIS_HELP})")

    args = parser.parse_args()

    if args.list:
        agents_dir = get_agents_dir(args.agents_dir, args.cwd)
        agents = list_agents(agents_dir)
        print(json.dumps({"agents": agents, "agents_dir": agents_dir}, ensure_ascii=False))
        sys.exit(0)

    if not args.prompt:
        _print_error("Missing required argument: --prompt.")
        sys.exit(1)
    if not args.cwd:
        _print_error("Missing required argument: --cwd.")
        sys.exit(1)
    if not os.path.isabs(args.cwd):
        _print_error(f"Invalid --cwd {args.cwd!r}: expected an absolute path.")
        sys.exit(1)
    if not os.path.isdir(args.cwd):
        _print_error(f"Invalid --cwd {args.cwd!r}: directory does not exist.")
        sys.exit(1)

    agents_dir = get_agents_dir(args.agents_dir, args.cwd)

    role_names = args.agent_names or []
    try:
        (
            run_agent_cli,
            system_context,
            permission,
            model,
            effort,
        ) = _compose_role_context(agents_dir, role_names)
    except (FileNotFoundError, ValueError) as e:
        _print_error(str(e))
        sys.exit(1)

    cli = args.cli or resolve_cli(run_agent_cli)
    invocation = AgentInvocation(
        cli=cli,
        prompt=args.prompt,
        cwd=args.cwd,
        system_context=system_context,
        # Multiple descriptors cannot be represented by provider-specific
        # single-file environment variables; their bodies are composed above.
        agent_file=None,
        permission=permission,
        model=model,
        effort=effort,
    )

    try:
        result = execute_agent(invocation, timeout_ms=args.timeout)
    except ValueError as e:
        _print_error(str(e), cli=cli)
        sys.exit(1)

    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0 if result["status"] == "success" else 1)


if __name__ == "__main__":
    main()
