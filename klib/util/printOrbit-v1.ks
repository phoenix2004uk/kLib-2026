{
	function convertOrbitToTextLines {
		parameter targetOrbit.
		if not targetOrbit:istype("Orbit") {
			return ApiFail("An Orbit must be specified").
		}
		local lines is list().
		lines:add("ORBITINFO: " + targetOrbit:tostring).
		lines:add("name = " + targetOrbit:name).
		lines:add("a = " + targetOrbit:semimajoraxis).
		lines:add("b = " + targetOrbit:semiminoraxis).
		lines:add("e = " + targetOrbit:eccentricity).
		lines:add("i = " + targetOrbit:inclination).
		lines:add("Ω = " + targetOrbit:lan).
		lines:add("ω = " + targetOrbit:argumentofperiapsis).
		lines:add("ra = " + (choose targetOrbit:apoapsis if targetOrbit:eccentricity < 1 else false)).
		lines:add("rp = " + targetOrbit:periapsis).
		lines:add("t0 = " + targetOrbit:epoch).
		lines:add("M0 = " + targetOrbit:meananomalyatepoch).
		lines:add("V0 = " + targetOrbit:trueanomaly).
		lines:add("P = " + (choose targetOrbit:period if targetOrbit:eccentricity < 1 else false)).
		lines:add("body = " + targetOrbit:body).
		lines:add("transition = " + targetOrbit:transition).
		lines:add("position = " + targetOrbit:position).
		lines:add("velocity:orbit = " + targetOrbit:velocity:orbit).
		lines:add("velocity:surface = " + targetOrbit:velocity:surface).
		lines:add("nextpatcheta = " + targetOrbit:nextpatcheta).
		lines:add("nextpatchat = " + (time:seconds + targetOrbit:nextpatcheta)).
		lines:add("hasnextpatch = " + targetOrbit:hasnextpatch).

		return ApiOK(lines).
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
		"lines", convertOrbitToTextLines@,
		"print", printOrbit@
	)).
}