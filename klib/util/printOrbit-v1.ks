{
	// Note: You cannot use these functions to query `Sun:orbit` (or the ultimate root body:orbit of a modded solarsystem/galaxy)
	//		as several parameters become Infinity/NaN and there is no reliable safe way to determine this, except for `Sun` in the standard solar system.
	//		We can only detect and reject `Sun` or the root body, not it's `:orbit` directly, which exists even if `hasorbit` is false.

	function convertOrbitToLex {
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
		local isParabolic is e = 1.
		local isElliptical is e < 1.

		// Cache velocity for querying both `:orbit` and `:surface`
		local queryVelocity is queryOrbit:velocity.

		local hasTransition is queryOrbit:transition <> "INITIAL" and queryOrbit:transition <> "FINAL".
		// Cache transitionEta and transitionAt calculated close to the same physics frame
		local transitionEta is "Infinity".
		local transitionAt is "Infinity".
		if hasTransition {
			set transitionEta to queryOrbit:nextpatcheta.
			set transitionAt to time:seconds + transitionEta.
		}

		// Note: virtual-orbits created using `createOrbit` do not actually track a virtual-orbitable despite the documentation.
		//		At any UT, trueanomaly is always 0, and position/velocity vectors are invalid V(NaN, NaN, NaN).
		//		Accessing the position/velocity will not crash kOS, but accessing the x/y/z/mag etc of those vectors *will* crash kOS with pushing NaN to the stack.
		entries:add("name", targetOrbit:tostring).
		entries:add("virtual", (choose "maybe" if queryOrbit:trueanomaly = 0 else "no")). // This will always be exactly 0 for a virtual-orbit, so virtual = maybe | no
		entries:add("a", queryOrbit:semimajoraxis).
		entries:add("b", choose "Infinity" if isParabolic else queryOrbit:semiminoraxis).
		entries:add("e", e).
		entries:add("i", queryOrbit:inclination).
		entries:add("Ω", queryOrbit:lan).
		entries:add("w", queryOrbit:argumentofperiapsis).
		entries:add("Ap", choose queryOrbit:apoapsis if isElliptical else "Infinity").
		entries:add("Pe", queryOrbit:periapsis).
		entries:add("t0", queryOrbit:epoch).
		entries:add("M0", queryOrbit:meananomalyatepoch).
		entries:add("V0", queryOrbit:trueanomaly). // This will be 0 for a virtual-orbit
		entries:add("P", choose queryOrbit:period if isElliptical else "Infinity").
		entries:add("body", queryOrbit:body:name).
		entries:add("transition", queryOrbit:transition).
		entries:add("position", queryOrbit:position). // This will be V(NaN, NaN, NaN) for a virtual-orbit
		entries:add("velocity:orbit", queryVelocity:orbit). // This will be V(NaN, NaN, NaN) for a virtual-orbit
		entries:add("velocity:surface", queryVelocity:surface). // This will be V(NaN, NaN, NaN) for a virtual-orbit
		entries:add("transitioneta", transitionEta).
		entries:add("transitionat", transitionAt).
		entries:add("hasnextpatch", queryOrbit:hasnextpatch).

		return ApiOK(entries).
	}

	function convertOrbitToTextLines {
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
		else return lexResult.
	}

	function printOrbit {
		parameter targetOrbit, printFn is {parameter line. print line.}.

		local linesResult is convertOrbitToTextLines(targetOrbit).
		if linesResult:ok {
			for line in linesResult:val {
				printFn(line).
			}
		}
		else { printFn(linesResult:msg). }
	}

	export(lex(
		"lex", convertOrbitToLex@,
		"lines", convertOrbitToTextLines@,
		"print", printOrbit@
	)).
}