# bash completion for pasbuild
#
# Features:
# - Suggest exactly one goal in goal position.
# - Treat -h/--help, --version, and --license as top-level informational flags.
# - Do not suggest informational flags after a goal is present.
# - Complete files for -f/--file and --fpc.
# - Complete modules and profiles from project.xml when possible.
# - Also suggest goals discovered in <project-dir>/plugins/ ~/.pasbuild/plugins/ and path.
# - Support comma-separated profile completion.
# Uses "pasbuild resolve" as the source of truth for:
# - availableProfiles
# - modules[].name
#
# Ignores non-JSON log lines beginning with:
#   [INFO]
#   [WARN]
#   [ERROR]
#
# Install:
#   source ./pasbuild-completion.bash
# or copy to the file:
#   ~/.local/share/bash-completion/completions/pasbuild <- not a directory, but the filename "pasbuild"

_pasbuild_builtin_goals=(
    clean
    process-resources
    compile
    process-test-resources
    test-compile
    test
    package
    source-package
    lazarus-package
    install
    dependency-tree
    resolve
    init
)

_pasbuild_info_opts=(
    -h
    --help
    --version
    --license
)

_pasbuild_build_opts=(
    -p
    --profile
    -f
    --file
    --fpc
    -v
    --verbose
)

_pasbuild_module_opts=(
    -m
    --module
)

_pasbuild_init_completion_fallback() {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev=""
    (( COMP_CWORD > 0 )) && prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
}

_pasbuild_init() {
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n : || return
    else
        _pasbuild_init_completion_fallback
    fi
}

_pasbuild_get_goal() {
    local i arg
    for (( i=1; i<COMP_CWORD; i++ )); do
        arg="${COMP_WORDS[i]}"
        case "$arg" in
            clean|process-resources|compile|process-test-resources|test-compile|test|package|source-package|lazarus-package|install|dependency-tree|resolve|init)
                printf '%s\n' "$arg"
                return
                ;;
            -*)
                ;;
            *)
                printf '%s\n' "$arg"
                return
                ;;
        esac
    done
    return 1
}

_pasbuild_has_info_opt() {
    local i arg
    for (( i=1; i<COMP_CWORD; i++ )); do
        arg="${COMP_WORDS[i]}"
        case "$arg" in
            -h|--help|--version|--license)
                return 0
                ;;
        esac
    done
    return 1
}

_pasbuild_goal_supports_module() {
    case "$1" in
        compile|resolve|dependency-tree|install) return 0 ;;
        *) return 1 ;;
    esac
}

_pasbuild_get_project_dir_from_file() {
    local file="$1"
    if [[ "$file" == */* ]]; then
        local dir="${file%/*}"
        [[ -n "$dir" ]] || dir="."
        printf '%s\n' "$dir"
    else
        printf '%s\n' "."
    fi
}

_pasbuild_get_selected_file() {
    local i arg next
    local file="project.xml"

    for (( i=1; i<COMP_CWORD; i++ )); do
        arg="${COMP_WORDS[i]}"
        next="${COMP_WORDS[i+1]}"
        case "$arg" in
            -f|--file)
                if [[ -n "$next" ]]; then
                    file="$next"
                    ((i++))
                fi
                ;;
            --file=*)
                file="${arg#--file=}"
                ;;
        esac
    done

    printf '%s\n' "$file"
}

_pasbuild_get_selected_module() {
    local i arg next
    for (( i=1; i<COMP_CWORD; i++ )); do
        arg="${COMP_WORDS[i]}"
        next="${COMP_WORDS[i+1]}"
        case "$arg" in
            -m|--module)
                # Ignore if the module value is the current word being completed
                if (( i + 1 == COMP_CWORD )); then
                    return 1
                fi
                if [[ -n "$next" ]]; then
                    printf '%s\n' "$next"
                    return
                fi
                ;;
            --module=*)
                # Ignore if this is the current word being completed
                if (( i == COMP_CWORD )); then
                    return 1
                fi
                printf '%s\n' "${arg#--module=}"
                return
                ;;
        esac
    done
    return 1
}

_pasbuild_get_selected_profiles_raw() {
    local i arg next
    for (( i=1; i<COMP_CWORD; i++ )); do
        arg="${COMP_WORDS[i]}"
        next="${COMP_WORDS[i+1]}"
        case "$arg" in
            -p|--profile)
                if [[ -n "$next" ]]; then
                    printf '%s\n' "$next"
                    return
                fi
                ;;
            --profile=*)
                printf '%s\n' "${arg#--profile=}"
                return
                ;;
        esac
    done
    return 1
}

_pasbuild_get_plugin_goals() {
    local file project_dir
    file="$(_pasbuild_get_selected_file)"
    project_dir="$(_pasbuild_get_project_dir_from_file "$file")"

    {
        if [[ -d "$project_dir/plugins" ]]; then
            local f name
            for f in "$project_dir"/plugins/pasbuild-*; do
                [[ -e "$f" && -f "$f" && -x "$f" ]] || continue
                name="${f##*/}"
                name="${name#pasbuild-}"
                [[ -n "$name" ]] && printf '%s\n' "$name"
            done
        fi

        if [[ -d "$HOME/.pasbuild/plugins" ]]; then
            local f name
            for f in "$HOME"/.pasbuild/plugins/pasbuild-*; do
                [[ -e "$f" && -f "$f" && -x "$f" ]] || continue
                name="${f##*/}"
                name="${name#pasbuild-}"
                [[ -n "$name" ]] && printf '%s\n' "$name"
            done
        fi

        if [[ -n "$PATH" ]]; then
            local oldifs="$IFS"
            local dir f name
            IFS=':'
            for dir in $PATH; do
                [[ -n "$dir" && -d "$dir" ]] || continue
                for f in "$dir"/pasbuild-*; do
                    [[ -e "$f" && -f "$f" && -x "$f" ]] || continue
                    name="${f##*/}"
                    name="${name#pasbuild-}"
                    [[ -n "$name" ]] && printf '%s\n' "$name"
                done
            done
            IFS="$oldifs"
        fi
    } | awk 'NF && !seen[$0]++'
}

_pasbuild_get_all_goals() {
    {
        printf '%s\n' "${_pasbuild_builtin_goals[@]}"
        _pasbuild_get_plugin_goals
    } | awk 'NF && !seen[$0]++'
}

_pasbuild_resolve_json() {
    local root_file selected_module
    root_file="$(_pasbuild_get_selected_file)"
    selected_module="$(_pasbuild_get_selected_module 2>/dev/null || true)"

    local -a cmd
    cmd=(pasbuild resolve)

    if [[ -n "$root_file" ]]; then
        cmd+=(-f "$root_file")
    fi

    if [[ -n "$selected_module" ]]; then
        cmd+=(-m "$selected_module")
    fi

    local out
    out="$("${cmd[@]}" 2>/dev/null | grep -vE '^\[(INFO|WARN|ERROR)\]')"

    [[ -n "$out" ]] || return 1

    printf '%s\n' "$out"
}

_pasbuild_get_profiles() {
    local json
    json="$(_pasbuild_resolve_json)" || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '
            (.availableProfiles // [])
            | map(tostring | select(length > 0))
            | unique
            | .[]
        '
    else
        # fallback to old awk/sed if jq missing (optional)
        printf '%s\n' "$json" \
            | tr '\n' ' ' \
            | sed -n 's/.*"availableProfiles"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' \
            | grep -oE '"([^"\\]|\\.)*"' \
            | sed 's/^"//;s/"$//' \
            | awk 'NF && !seen[$0]++'
    fi
}

_pasbuild_get_modules() {
    local json
    json="$(_pasbuild_resolve_json)" || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '
            (.modules // [])
            | map(.name // empty | tostring | select(length > 0))
            | unique
            | .[]
        '
    else
        # fallback to old awk/sed if jq missing (optional)
        printf '%s\n' "$json" \
            | tr '\n' ' ' \
            | grep -oE '"name"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
            | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//; s/"$//' \
            | awk 'NF && !seen[$0]++'
    fi
}

_pasbuild_complete_profiles() {
    local cur="$1"
    local prefix part
    local -a avail used filtered

    if [[ "$cur" == *,* ]]; then
        prefix="${cur%,*}"
        part="${cur##*,}"
    else
        prefix=""
        part="$cur"
    fi

    mapfile -t avail < <(_pasbuild_get_profiles)
    IFS=',' read -r -a used <<< "$cur"

    local p u skip
    for p in "${avail[@]}"; do
        skip=0
        for u in "${used[@]}"; do
            [[ "$u" == "$part" ]] && continue
            [[ "$u" == "$p" ]] && { skip=1; break; }
        done
        [[ $skip -eq 0 ]] && filtered+=("$p")
    done

    COMPREPLY=($(compgen -W "${filtered[*]}" -- "$part"))

    if [[ -n "$prefix" ]]; then
        local i
        for i in "${!COMPREPLY[@]}"; do
            COMPREPLY[$i]="$prefix,${COMPREPLY[$i]}"
        done
    fi
}

_pasbuild_complete_files() {
    local mode="$1"
    case "$mode" in
        file|exe)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -f -- "$cur"))
            ;;
    esac
}

_pasbuild() {
    local cur prev words cword
    _pasbuild_init || return

    local goal
    goal="$(_pasbuild_get_goal)"

    if _pasbuild_has_info_opt; then
        COMPREPLY=()
        return
    fi

    case "$prev" in
        -f|--file)
            _pasbuild_complete_files file
            return
            ;;
        --fpc)
            _pasbuild_complete_files exe
            return
            ;;
        -p|--profile)
            _pasbuild_complete_profiles "$cur"
            return
            ;;
        -m|--module)
            if _pasbuild_goal_supports_module "$goal"; then
                local modules IFS=$'\n'
                modules="$(_pasbuild_get_modules)"
                COMPREPLY=($(compgen -W "$modules" -- "$cur"))
            else
                COMPREPLY=()
            fi
            return
            ;;
    esac

    case "$cur" in
        --file=*)
            cur="${cur#--file=}"
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -f -- "$cur"))
            COMPREPLY=("${COMPREPLY[@]/#/--file=}")
            return
            ;;
        --fpc=*)
            cur="${cur#--fpc=}"
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -f -- "$cur"))
            COMPREPLY=("${COMPREPLY[@]/#/--fpc=}")
            return
            ;;
        --profile=*)
            cur="${cur#--profile=}"
            _pasbuild_complete_profiles "$cur"
            COMPREPLY=("${COMPREPLY[@]/#/--profile=}")
            return
            ;;
        --module=*)
            cur="${cur#--module=}"
            if _pasbuild_goal_supports_module "$goal"; then
                local modules IFS=$'\n'
                modules="$(_pasbuild_get_modules)"
                COMPREPLY=($(compgen -W "$modules" -- "$cur"))
                COMPREPLY=("${COMPREPLY[@]/#/--module=}")
            else
                COMPREPLY=()
            fi
            return
            ;;
    esac

    if [[ -z "$goal" ]]; then
        local all_goals
        all_goals="$(_pasbuild_get_all_goals)"
        COMPREPLY=($(compgen -W "$all_goals ${_pasbuild_info_opts[*]}" -- "$cur"))
        return
    fi

    local opts=("${_pasbuild_build_opts[@]}")
    if _pasbuild_goal_supports_module "$goal"; then
        opts+=("${_pasbuild_module_opts[@]}")
    fi

    COMPREPLY=($(compgen -W "${opts[*]}" -- "$cur"))
}

complete -F _pasbuild pasbuild
