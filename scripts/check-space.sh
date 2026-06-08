#!/bin/sh
# Exit 0 if the room's parent space name is in MATRIX_CUSTOM_SPACES (JSON array of strings).
# Exit 1 otherwise (no parent, name not in list, or any API error).
# Requires: MATRIX_SERVER, MATRIX_ACCESS_TOKEN, MATRIX_USER_ID, MATRIX_CUSTOM_SPACES env vars.

ROOM="$1"
[ -z "$ROOM" ] && exit 1

PARENTS=$(curl -sf \
  -H "Authorization: Bearer $MATRIX_ACCESS_TOKEN" \
  "$MATRIX_SERVER/_matrix/client/v3/rooms/$ROOM/state?user_id=$MATRIX_USER_ID" \
  | jq -r '.[] | select(.type == "m.space.parent") | .state_key')

[ -z "$PARENTS" ] && exit 1

for SPACE_ID in $PARENTS; do
  NAME=$(curl -sf \
    -H "Authorization: Bearer $MATRIX_ACCESS_TOKEN" \
    "$MATRIX_SERVER/_matrix/client/v3/rooms/$SPACE_ID/state/m.room.name?user_id=$MATRIX_USER_ID" \
    | jq -r '.name // empty')
  [ -z "$NAME" ] && continue
  if echo "$MATRIX_CUSTOM_SPACES" | jq -e --arg n "$NAME" 'any(.[]; . == $n)' >/dev/null 2>&1; then
    exit 0
  fi
done
exit 1
