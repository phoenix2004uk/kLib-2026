{
	local InfinityString is "Infinity".
	local convertOrbitToLex is {
		parameter targetOrbit.
		local queryOrbit is targetOrbit.
		if targetOrbit:istype("Body") {
			if not targetOrbit:hasorbit {
				return ApiFail("The root body does not have an orbit").
			}
			set queryOrbit to targetOrbit:orbit.
		}
		if targetOrbit:istype("Vessel") {
			set queryOrbit to targetOrbit:orbit.
		}
		if not queryOrbit:istype("Orbit") {
			return ApiFail("An Orbit, Vessel or Body must be specified").
		}
		local entries is lex().
		local e is queryOrbit:eccentricity.
		local queryVelocity is queryOrbit:velocity.
		local transitionEta is InfinityString.
		local transitionAt is InfinityString.
		if queryOrbit:transition <> "INITIAL" and queryOrbit:transition <> "FINAL" {
			set transitionEta to queryOrbit:nextpatcheta.
			set transitionAt to time:seconds + transitionEta.
		}
		entries:add("name", targetOrbit:tostring).
		entries:add("virtual", (choose "maybe" if queryOrbit:trueanomaly = 0 else "no")).
		entries:add("a", queryOrbit:semimajoraxis).
		entries:add("b", choose InfinityString if e = 1 else queryOrbit:semiminoraxis).
		entries:add("e", e).
		entries:add("i", queryOrbit:inclination).
		entries:add("Ω", queryOrbit:lan).
		entries:add("w", queryOrbit:argumentofperiapsis).
		entries:add("Ap", choose queryOrbit:apoapsis if e < 1 else InfinityString).
		entries:add("Pe", queryOrbit:periapsis).
		entries:add("t0", queryOrbit:epoch).
		entries:add("M0", queryOrbit:meananomalyatepoch).
		entries:add("V0", queryOrbit:trueanomaly).
		entries:add("P", choose queryOrbit:period if e < 1 else InfinityString).
		entries:add("body", queryOrbit:body:name).
		entries:add("transition", queryOrbit:transition).
		entries:add("position", queryOrbit:position).
		entries:add("velocity:orbit", queryVelocity:orbit).
		entries:add("velocity:surface", queryVelocity:surface).
		entries:add("transitioneta", transitionEta).
		entries:add("transitionat", transitionAt).
		entries:add("hasnextpatch", queryOrbit:hasnextpatch).
		return ApiOK(entries).
	}.
	local convertOrbitToTextLines is {
		parameter targetOrbit.
		local lexResult is convertOrbitToLex(targetOrbit).
		if lexResult:ok {
			local entries is lexResult:val.
			local lines is list().
			local maxKeyLength is 0.
			for key in entries:keys set maxKeyLength to max(maxKeyLength, key:length).
			for key in entries:keys {
				lines:add(key:padright(maxKeyLength) + " = " + entries[key]).
			}
			return ApiOK(lines).
		}
		return lexResult.
	}.
	export(lex(
		"lex", convertOrbitToLex,
		"lines", convertOrbitToTextLines,
		"print", {
			parameter targetOrbit, printFn is {parameter line. print line.}.
			local linesResult is convertOrbitToTextLines(targetOrbit).
			if linesResult:ok {
				for line in linesResult:val {
					printFn(line).
				}
			}
			else { printFn(linesResult:msg). }
		}
	)).
}