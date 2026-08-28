{
	// Create a fresh configuration lex from a defaults lex and caller overrides.
	// Unknown option keys are rejected rather than silently ignored.
	function createConfigFromExclusiveDefaults {
		parameter defaults, options is lex().

		if not defaults:istype("Lexicon") {
			return ApiFail("Configuration defaults must be a Lexicon").
		}
		if not options:istype("Lexicon") {
			return ApiFail("Configuration options must be a Lexicon").
		}

		local cfg is lex().

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

	export(createConfigFromExclusiveDefaults@).
}