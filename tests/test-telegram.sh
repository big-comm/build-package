#!/usr/bin/env bash
# One Telegram message per build: send_telegram_message (defined in action.yml)
# sends the first and edits it after. A fake curl answers like the Bot API.
set -Eeuo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The function as action.yml writes it, with the inputs filled in.
python3 - "$here/../action.yml" "$work/telegram.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
body = text.split("cat << 'EOF' > /tmp/send_telegram_message.sh\n", 1)[1].split("\n        EOF\n", 1)[0]
body = "\n".join(line[8:] for line in body.splitlines())
body = body.replace("${{ inputs.telegram_token }}", "TOKEN").replace("${{ inputs.telegram_chat_id }}", "1")
open(sys.argv[2], "w").write(body + "\n")
PY

mkdir "$work/bin"
cat > "$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
for arg; do
    case $arg in
        */sendMessage) method=sendMessage ;;
        */editMessageText) method=editMessageText ;;
        message_id=*) id=${arg#message_id=} ;;
    esac
done
echo "$method" >> "$CALLS"
case $method in
    sendMessage) echo '{"ok":true,"result":{"message_id":'"$NEXT_ID"',"chat":{"id":1}}}' ;;
    # EDIT_ANSWER is the answer about the message the build started with (7).
    editMessageText) [[ $id == 7 ]] && echo "$EDIT_ANSWER" || echo '{"ok":true}' ;;
esac
FAKE
chmod +x "$work/bin/curl"

fail=0
check() {  # check NAME EXPECTED ACTUAL
    if [[ $2 == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1: expected [$2], got [$3]"; fail=1; fi
}

run() {  # run STORED_ID EDIT_ANSWER: two messages in a row
    : > "$work/calls"
    if [[ -n $1 ]]; then echo "$1" > "$work/id"; else rm -f "$work/id"; fi
    PATH="$work/bin:$PATH" CALLS="$work/calls" NEXT_ID=42 EDIT_ANSWER=$2 \
        TELEGRAM_MESSAGE_ID_FILE="$work/id" bash -c \
        'source "$1"; send_telegram_message "<b>step</b>" >/dev/null 2>&1; send_telegram_message "<b>next</b>" >/dev/null 2>&1' \
        _ "$work/telegram.sh"
}

run '' '{"ok":true}'
check 'the first message is sent, the next one edits it' 'sendMessage editMessageText' "$(paste -sd' ' "$work/calls")"
check 'its id is kept for the later steps' '42' "$(cat "$work/id")"

run 7 '{"ok":true,"result":{}}'
check 'a known id is edited, never a new message' 'editMessageText editMessageText' "$(paste -sd' ' "$work/calls")"

run 7 '{"ok":false,"description":"Bad Request: message to edit not found"}'
check 'a message that cannot be edited is sent anew, then that one is edited' \
    'editMessageText sendMessage editMessageText' "$(paste -sd' ' "$work/calls")"
check 'the new id replaces the old one' '42' "$(cat "$work/id")"

run 7 '{"ok":false,"description":"Bad Request: message is not modified"}'
check 'the same text again is not a new message' 'editMessageText editMessageText' "$(paste -sd' ' "$work/calls")"

# The text sent: a message written inside an indented block loses that indentation.
cat > "$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
for arg; do [[ $arg == text=* ]] && printf '%s' "${arg#text=}" > "$TEXT"; done
echo '{"ok":true,"result":{"message_id":1}}'
FAKE
rm -f "$work/id"
PATH="$work/bin:$PATH" TEXT="$work/text" TELEGRAM_MESSAGE_ID_FILE="$work/id" bash -c \
    'source "$1"; send_telegram_message "<b>title</b>
            <b>line</b>" >/dev/null 2>&1' _ "$work/telegram.sh"
check 'the indentation of the block is not sent' $'<b>title</b>\n<b>line</b>' "$(cat "$work/text")"

helper() {  # helper CODE -> output of CODE with the helpers defined
    GITHUB_TRIGGERING_ACTOR='a<b' GITHUB_ACTOR=other bash -c 'source "$1"; eval "$2"' _ "$work/telegram.sh" "$1"
}
# shellcheck disable=SC2016  # expanded by the helper's shell
check 'sizes read as a person would' '900 B|1.2 MB|3.0 GB' \
    "$(helper 'printf "%s|%s|%s" "$(tg_size 900)" "$(tg_size 1258291)" "$(tg_size 3221225472)"')"
# shellcheck disable=SC2016  # expanded by the helper's shell
check 'each branch has its icon' '🧪✅🧩🚀🐧❔' \
    "$(helper 'for b in testing Stable extra priority aur other; do tg_branch_icon "$b"; done')"
check 'the branch line names the source branch' '🧪 <b>Branch:</b> testing (dev-x)' "$(helper 'tg_branch testing dev-x')"
check 'who triggered the build, escaped' '👤 <b>Built by:</b> <code>a&lt;b</code>' "$(helper "tg_actor 'Built by'")"

((fail == 0)) && echo && echo 'all passed'
exit "$fail"
