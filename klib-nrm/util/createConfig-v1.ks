{
	export({
		parameter defaults, options is lex().
		local cfg is lex().
		local messagePrefix is "Configuration ".
		local messageTail is " must be a Lexicon".
		if defaults:istype("Lexicon") {
			if options:istype("Lexicon") {
				for key in defaults:keys {
					cfg:add(key, defaults[key]).
				}
				for key in options:keys {
					if not cfg:haskey(key) {
						return ApiFail("Unknown configuration option: " + key).
					}
					set cfg[key] to options[key].
				}
				return ApiOK(cfg).
			}
			return ApiFail(messagePrefix + "options" + messageTail).
		}
		return ApiFail(messagePrefix + "defaults" + messageTail).
	}).
}