{
	local MAX_TERRAIN_HEIGHTS is lex(
		"Sun", 0,
		"Kerbin", 6760,
		"Mun", 7057,
		"Minmus", 5725,
		"Moho", 6816,
		"Eve", 7537,
		"Duna", 8264,
		"Ike", 12734,
		"Jool", 0,
		"Laythe", 6060,
		"Vall", 7975,
		"Bop", 21755,
		"Tylo", 12894,
		"Gilly", 6401,
		"Pol", 4889,
		"Dres", 5670,
		"Eeloo", 3795,
		"Sarnus", 0,
		"Hale", 5918,
		"Ovok", 14000,
		"Slate", 16398,
		"Tekto", 5873,
		"Urlum", 0,
		"Polta", 8649,
		"Priax", 30483,
		"Wal", 20773,
		"Tal", 11777,
		"Neidon", 0,
		"Thatmo", 4825,
		"Nissee", 8936,
		"Plock", 3330,
		"Karen", 4604
	).
	function selectBody {
		parameter targetBodyQuery.
		if targetBodyQuery:istype("Body") return ApiOK(targetBodyQuery).
		else if targetBodyQuery:istype("string") and bodyExists(targetBodyQuery) return ApiOK(body(targetBodyQuery)).
		else return ApiFail(targetBodyQuery:tostring + " is not a valid Body").
	}
	function getSafeAltitude {
		parameter targetBodyQuery, includeAtmosphereHeight is true.
		local selectBodyResult is selectBody(targetBodyQuery).
		if not selectBodyResult:ok return selectBodyResult.
		local targetBody is selectBodyResult:val,
			targetBodyName is targetBody:name.
		if not MAX_TERRAIN_HEIGHTS:haskey(targetBodyName) return ApiFail(targetBodyQuery:tostring + " does not have a known maximum terrain height").
		return ApiOK(max(choose targetBody:atm:height if includeAtmosphereHeight and targetBody:atm:exists else 0, MAX_TERRAIN_HEIGHTS[targetBodyName])).
	}
	export(lex(
		"altitude", getSafeAltitude@,
		"radius", {
			parameter targetBodyQuery, includeAtmosphereHeight is true.
			local selectBodyResult is selectBody(targetBodyQuery).
			if not selectBodyResult:ok return selectBodyResult.
			local targetBody is selectBodyResult:val,
				altitudeResult is getSafeAltitude(targetBody, includeAtmosphereHeight).
			if not altitudeResult:ok return altitudeResult.
			return ApiOK(altitudeResult:val + targetBody:radius).
		}
	)).
}