extends RefCounted
## NetProtocol.gd — the small, transport-independent Skirmish wire contract.
##
## Every partner message (DIRECT or RELAY) crosses the wire in this envelope:
##   {"pv": 1, "sid": "…", "seq": 7, "k": "intent", "p": {…}}
##
## The engine RPC signature checksum only proves that both builds expose matching
## RPC methods.  This envelope additionally rejects stale sessions, duplicate or
## reordered application messages, unknown message families, object payloads and
## unreasonably large/deep Dictionaries before gameplay code sees them.

const VERSION: int = 2
const MAX_WIRE_BYTES: int = 131072
const MAX_NODES: int = 4096
const MAX_DEPTH: int = 10
const MAX_DICT_KEYS: int = 96
const MAX_ARRAY_ITEMS: int = 256
const MAX_STRING_BYTES: int = 8192
const FINGERPRINT_HEX_LENGTH: int = 64

const KIND_READY := "ready"
const KIND_HERO := "hero"
const KIND_MATCH_START := "mstart"
const KIND_MATCH_CONFIG := "mcfg"
const KIND_DRAFT := "draft"
const KIND_INTENT := "intent"
const KIND_EVENT := "event"
const KIND_LAUNCH := "launch"

const ALLOWED_KINDS: Array[String] = [
	KIND_READY,
	KIND_HERO,
	KIND_MATCH_START,
	KIND_MATCH_CONFIG,
	KIND_DRAFT,
	KIND_INTENT,
	KIND_EVENT,
	KIND_LAUNCH,
]


static func make_envelope(kind: String, payload: Dictionary, session_id: String,
		sequence: int) -> Dictionary:
	return {
		"pv": VERSION,
		"sid": session_id,
		"seq": sequence,
		"k": kind,
		"p": payload,
	}


## Empty string means valid.  Any other result is a stable rejection reason that
## probes and relay logs can assert without depending on engine error wording.
static func validate_envelope(wire: Variant, expected_session: String = "") -> String:
	if typeof(wire) != TYPE_DICTIONARY:
		return "wire_not_dictionary"
	var env: Dictionary = wire
	if int(env.get("pv", -1)) != VERSION:
		return "protocol_version"
	var sid_value: Variant = env.get("sid", null)
	if typeof(sid_value) != TYPE_STRING:
		return "session_type"
	var sid := String(sid_value)
	if sid.is_empty() or sid.length() > 64:
		return "session_invalid"
	if not expected_session.is_empty() and sid != expected_session:
		return "session_mismatch"
	var seq_value: Variant = env.get("seq", null)
	if typeof(seq_value) != TYPE_INT or int(seq_value) <= 0:
		return "sequence_invalid"
	var kind_value: Variant = env.get("k", null)
	if typeof(kind_value) != TYPE_STRING:
		return "kind_type"
	var kind := String(kind_value)
	if kind not in ALLOWED_KINDS:
		return "kind_unknown"
	var payload_value: Variant = env.get("p", null)
	if typeof(payload_value) != TYPE_DICTIONARY:
		return "payload_not_dictionary"
	var budget := {"nodes": 0}
	if not _is_safe_value(env, 0, budget):
		return "payload_shape"
	if int(budget.nodes) > MAX_NODES:
		return "payload_nodes"
	if var_to_bytes(env).size() > MAX_WIRE_BYTES:
		return "payload_size"
	return _validate_kind_payload(kind, payload_value)


static func payload(wire: Dictionary) -> Dictionary:
	return wire.get("p", {}) as Dictionary


static func kind(wire: Dictionary) -> String:
	return String(wire.get("k", ""))


static func sequence(wire: Dictionary) -> int:
	return int(wire.get("seq", 0))


static func session(wire: Dictionary) -> String:
	return String(wire.get("sid", ""))


static func wire_size(wire: Dictionary) -> int:
	return var_to_bytes(wire).size()


## Canonical SHA-256 for the live compatibility snapshot assembled by NetMatch.
## Dictionary insertion order never enters the digest: keys are encoded first,
## sorted by that encoding, then paired with their recursively encoded values.
static func compatibility_fingerprint(snapshot: Variant) -> String:
	return _canonical_compat_value(snapshot).sha256_text()


static func valid_fingerprint(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var fingerprint := String(value)
	if fingerprint.length() != FINGERPRINT_HEX_LENGTH:
		return false
	for ch in fingerprint:
		var c := String(ch)
		if not (c >= "0" and c <= "9") and not (c >= "a" and c <= "f"):
			return false
	return true


static func _canonical_compat_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "n;"
		TYPE_BOOL:
			return "b1;" if bool(value) else "b0;"
		TYPE_INT:
			return "i%s;" % String.num_int64(int(value))
		TYPE_STRING, TYPE_STRING_NAME:
			var encoded := String(value).to_utf8_buffer().hex_encode()
			return "s%d:%s;" % [encoded.length(), encoded]
		TYPE_ARRAY:
			var out := "a%d[" % (value as Array).size()
			for item in value as Array:
				out += _canonical_compat_value(item)
			return out + "];"
		TYPE_DICTIONARY:
			var entries: Array[Dictionary] = []
			for key in value as Dictionary:
				entries.append({
					"encoded": _canonical_compat_value(key),
					"key": key,
				})
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.encoded) < String(b.encoded))
			var out := "d%d{" % entries.size()
			for entry in entries:
				out += String(entry.encoded)
				out += _canonical_compat_value((value as Dictionary)[entry.key])
			return out + "};"
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL:
			# Compatibility snapshots must be pure data. Keep an unmistakable,
			# deterministic marker if a future registry accidentally adds one.
			return "unsupported:%d;" % typeof(value)
		_:
			# Floats, colours, vectors and packed arrays have deterministic
			# Variant byte encodings in a fixed Godot protocol version.
			var encoded := var_to_bytes(value).hex_encode()
			return "v%d:%d:%s;" % [typeof(value), encoded.length(), encoded]


static func _validate_kind_payload(kind_id: String, p: Dictionary) -> String:
	match kind_id:
		KIND_READY:
			if typeof(p.get("value", null)) != TYPE_BOOL:
				return "ready_value"
		KIND_HERO:
			if typeof(p.get("hero", null)) != TYPE_STRING \
					or String(p.get("hero", "")).length() > 64:
				return "hero_value"
		KIND_MATCH_START:
			if not _has_ints(p, ["seed", "mode", "bo", "style"]):
				return "match_start_fields"
			if typeof(p.get("h0", "")) != TYPE_STRING or typeof(p.get("h1", "")) != TYPE_STRING:
				return "match_start_heroes"
		KIND_MATCH_CONFIG:
			if not _has_ints(p, ["mode", "bo", "style"]):
				return "match_config_fields"
		KIND_DRAFT:
			if typeof(p.get("event", null)) != TYPE_DICTIONARY \
					or typeof((p.get("event", {}) as Dictionary).get("t", null)) != TYPE_STRING:
				return "draft_event"
		KIND_INTENT:
			if typeof(p.get("intent", null)) != TYPE_DICTIONARY \
					or typeof((p.get("intent", {}) as Dictionary).get("t", null)) != TYPE_STRING:
				return "intent_event"
		KIND_EVENT:
			if typeof(p.get("event", null)) != TYPE_DICTIONARY \
					or typeof((p.get("event", {}) as Dictionary).get("t", null)) != TYPE_STRING:
				return "authoritative_event"
		KIND_LAUNCH:
			if not p.is_empty():
				return "launch_payload"
	return ""


static func _has_ints(data: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if typeof(data.get(key, null)) != TYPE_INT:
			return false
	return true


static func _is_safe_value(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth > MAX_DEPTH:
		return false
	budget.nodes = int(budget.nodes) + 1
	if int(budget.nodes) > MAX_NODES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return true
		TYPE_STRING:
			return String(value).to_utf8_buffer().size() <= MAX_STRING_BYTES
		TYPE_ARRAY:
			var arr: Array = value
			if arr.size() > MAX_ARRAY_ITEMS:
				return false
			for item in arr:
				if not _is_safe_value(item, depth + 1, budget):
					return false
			return true
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			if dict.size() > MAX_DICT_KEYS:
				return false
			for key in dict:
				if typeof(key) != TYPE_STRING \
						or String(key).to_utf8_buffer().size() > 128:
					return false
				if not _is_safe_value(dict[key], depth + 1, budget):
					return false
			return true
	return false
