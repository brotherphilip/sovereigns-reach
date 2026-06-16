extends RefCounted
# Tiny coordinator so only ONE blocking popup (world-event choice / tribute demand)
# is shown at a time. Each modal panel joins GROUP and, before opening, checks
# other_visible(); if another modal is up it queues itself instead and is shown when
# the current one closes (the closer calls advance()). Keeps decisions readable
# instead of stacking two panels on top of each other.

const GROUP := "ui_modal"

# Is any OTHER modal in the group currently on screen?
static func other_visible(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	for n in node.get_tree().get_nodes_in_group(GROUP):
		if n != node and is_instance_valid(n) and n.visible:
			return true
	return false

# Called by a modal as it closes: hand off to the next queued modal, if any.
static func advance(closing: Node) -> void:
	if closing == null or not closing.is_inside_tree():
		return
	for n in closing.get_tree().get_nodes_in_group(GROUP):
		if n != closing and is_instance_valid(n) and n.has_method("show_if_queued"):
			if n.show_if_queued():
				return
