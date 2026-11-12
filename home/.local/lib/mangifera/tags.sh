# Sourced by goto-tag and window-edge.sh. Sets:
#   monitor    the focused monitor
#   tag        its tag, read from it rather than the focused window, as an
#              empty tag has none
#   last       its last tag
# and defines capped_tag.

read -r monitor tag last < <(mmsg get all-monitors | jq -r '
	[.monitors[] | select(.active)][0] |
	"\(.name) \([.tags[] | select(.is_active)][0].index) \(.tag_num)"')

# Prints the tag to land on instead of $1 on the focused monitor, so going to
# an empty tag never goes past the first empty one: with windows on 1-4, 9
# becomes 5, and with windows on 1, 2 and 5 it becomes 3. A tag with windows
# is itself. Windows parked in the scratchpad don't count, as on the bar, nor
# do global ones (picture-in-picture), which follow onto every tag, nor does
# the window with id $2, when it's the one being moved.
capped_tag() {
	mmsg get all-clients | jq -r --arg m "$monitor" --argjson t "$1" \
		--argjson skip "${2:-0}" --argjson last "$last" '
		[.clients[] | select(.monitor == $m and
			(.is_minimized or .is_global | not) and .id != $skip) | .tags[]] as $used |
		if $used | index($t) then $t
		else first(range(1; $last + 1) | select(. as $i | $used | index($i) | not)) // $t
		end'
}
