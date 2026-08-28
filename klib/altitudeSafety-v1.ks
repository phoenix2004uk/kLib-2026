{
	// TODO: Once calculation is implemented, we will actually store this in a flattened file to be read, instead of hard-coded lex loaded at runtime
	local MAX_TERRAIN_HEIGHTS is lex(
		"Sun", 0,
		"Kerbin", 0,
		"Mun", 7500,
		"Minmus", 6e3,
		"Moho", 7e3,
		"Eve", 0,
		"Duna", 0,
		"Ike", 13e3,
		"Jool", 0,
		"Laythe", 0,
		"Vall", 8500,
		"Bop", 22e3,
		"Tylo", 12e3,
		"Gilly", 7e3,
		"Pol", 6e3,
		"Dres", 0,
		"Eeloo", 0,
		"Sarnus", 0,
		"Hale", 0,
		"Ovok", 0,
		"Slate", 0,
		"Tekto", 0,
		"Urlum", 0,
		"Polta", 0,
		"Priax", 0,
		"Wal", 0,
		"Tal", 0,
		"Neidon", 0,
		"Thatmo", 0,
		"Nissee", 0,
		"Plock", 0,
		"Karen", 0
	).

	// given either a Body object or a string, will attempt to return the Body object if it exists
	function selectBody {
		parameter targetBodyQuery.

		if targetBodyQuery:istype("Body") {
			return ApiOK(targetBodyQuery).
		}
		else if targetBodyQuery:istype("string") and bodyExists(targetBodyQuery) {
			return ApiOK(body(targetBodyQuery)).
		}
		// we use targetBodyQuery:tostring, so that if the caller uses the global `Mun` then we print Body("Mun"), if the caller uses the string "Mun" then we print "Mun"
		else return ApiFail(targetBodyQuery:tostring + " is not a valid Body").
	}

	function populateDatabase {
		local allBodies is list().
		list bodies in allBodies.
		for b in allBodies calculateMaxTerrainHeight(b).
	}

	// This function will calculate the max terrain height of the specified body, and store it in `MAX_TERRAIN_HEIGHTS`
	function calculateMaxTerrainHeight {
		parameter targetBodyQuery.

		local selectBodyResult is selectBody(targetBodyQuery).
		if not selectBodyResult:ok return selectBodyResult.

		local targetBody is selectBodyResult:val.
		if not targetBody:hasSolidSurface {
			set MAX_TERRAIN_HEIGHTS[targetBody:name] to 0.
			return ApiOK(true).
		}

		// TODO: iterate the surface to find the max altitude, for now just return with true
		return ApiOK(true).
	}

	function getSafeAltitude {
		parameter targetBodyQuery, includeAtmosphereHeight is true.

		local selectBodyResult is selectBody(targetBodyQuery).
		if not selectBodyResult:ok return selectBodyResult.

		local targetBody is selectBodyResult:val.
		local targetBodyName is targetBody:name.

		// we use targetBodyQuery:tostring, so that if the caller uses the global `Mun` then we print Body("Mun"), if the caller uses the string "Mun" then we print "Mun"
		if not MAX_TERRAIN_HEIGHTS:haskey(targetBodyName) return ApiFail(targetBodyQuery:tostring + " does not have a known maximum terrain height").

		local atmosphereHeight is choose targetBody:atm:height if includeAtmosphereHeight and targetBody:atm:exists else 0.
		local maxTerrainHeight is MAX_TERRAIN_HEIGHTS[targetBodyName].

		return ApiOK(max(atmosphereHeight, maxTerrainHeight)).
	}

	function getSafeRadius {
		parameter targetBodyQuery, includeAtmosphereHeight is true.

		local selectBodyResult is selectBody(targetBodyQuery).
		if not selectBodyResult:ok return selectBodyResult.

		local targetBody is selectBodyResult:val.
		local altitudeResult is getSafeAltitude(targetBody, includeAtmosphereHeight).
		if not altitudeResult:ok return altitudeResult.

		return ApiOK(altitudeResult:val + targetBody:radius).
	}

	export(lex(
		"altitude", getSafeAltitude@,
		"radius", getSafeRadius@,
		"calculate", calculateMaxTerrainHeight@,
		"calculateAll", populateDatabase@
	)).
}