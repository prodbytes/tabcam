# Sourced by the run scripts. DART_DEFINES holds a --dart-define for each
# allowed setting: from the environment when it's set there (scripts/deploy.sh
# sets the stage), otherwise from the repo's .env (see .env.example).
#
# Only the names below are passed: anything given to Flutter is compiled
# into the app (readable in the web bundle), so secrets in .env must never
# be listed here. Add public identifiers only.
_allowed=(TABSCAN_STAGE)
_env="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
DART_DEFINES=()
for _name in "${_allowed[@]}"; do
  _value="${!_name:-}"
  if [[ -z "$_value" && -f "$_env" ]]; then
    _value="$(sed -n "s/^${_name}=//p" "$_env" | tail -1)"
  fi
  [[ -n "$_value" ]] && DART_DEFINES+=(--dart-define="${_name}=${_value}")
done
unset _allowed _env _name _value
