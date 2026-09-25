# shellcheck shell=bash
# Bash completion for WSLMole.
# Installed to a bash-completion completions directory by install.sh.

_wslmole() {
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion || return
    else
        # Minimal fallback when bash-completion's helpers are unavailable.
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword="$COMP_CWORD"
    fi

    local commands="clean disk dev diagnose packages wsl scan plan fix update help"
    local global_opts="-h --help --version -i --interactive -q --quick -v --verbose --no-color --format -y --yes"

    # Find the subcommand (first non-option word after argv[0]).
    local i command=""
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            -*) ;;
            *) command="${words[i]}"; break ;;
        esac
    done

    # Complete the value for options that take an argument.
    case "$prev" in
        --format)
            mapfile -t COMPREPLY < <(compgen -W "text json" -- "$cur"); return ;;
        -m|--mode)
            mapfile -t COMPREPLY < <(compgen -W "summary tree files folders types old" -- "$cur"); return ;;
        --risk)
            mapfile -t COMPREPLY < <(compgen -W "low medium review" -- "$cur"); return ;;
        -c|--category|--only)
            mapfile -t COMPREPLY < <(compgen -W "apt snap logs tmp browser user wsl all" -- "$cur"); return ;;
        -t|--types)
            mapfile -t COMPREPLY < <(compgen -W "node_modules target __pycache__ venv .venv" -- "$cur"); return ;;
        -d|--depth|-n|--top|--older-than)
            return ;;  # numeric argument — no useful completion
    esac

    # No subcommand yet: complete commands and global options.
    if [[ -z "$command" ]]; then
        if [[ "$cur" == -* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "$global_opts" -- "$cur")
        else
            mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
        fi
        return
    fi

    # Per-subcommand completion.
    local sub_opts="" sub_args=""
    case "$command" in
        clean)
            sub_opts="-n --dry-run -f --force -c --category -h --help"
            sub_args="apt snap logs tmp browser user wsl all" ;;
        disk)
            sub_opts="-m --mode -d --depth -n --top -h --help" ;;
        dev)
            sub_opts="-n --dry-run -f --force -t --types --older-than -h --help" ;;
        diagnose)
            sub_opts="-h --help"
            sub_args="all process memory service wsl" ;;
        packages)
            sub_opts="-h --help"
            sub_args="audit update autoremove clean list" ;;
        wsl)
            sub_opts="-h --help"
            sub_args="info memory compact interop" ;;
        scan)
            sub_opts="-h --help" ;;
        plan)
            sub_opts="--risk --auto --category -h --help" ;;
        fix)
            sub_opts="-n --dry-run --only --yes -h --help" ;;
        update)
            sub_opts="-c --check -h --help" ;;
        help)
            sub_args="$commands" ;;
    esac

    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$sub_opts" -- "$cur")
    elif [[ -n "$sub_args" ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$sub_args" -- "$cur")
    elif [[ "$command" == "disk" || "$command" == "dev" ]]; then
        # These take a filesystem path argument.
        mapfile -t COMPREPLY < <(compgen -d -- "$cur")
    fi
}

complete -F _wslmole wslmole
