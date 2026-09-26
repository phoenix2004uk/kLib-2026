clearScreen.
local MAX_TERRAIN_HEIGHTS is lex(
	"Sun",       0,
	"Kerbin",    6760,
	"Mun",       7057,
	"Minmus",    5725,
	"Moho",      6816,
	"Eve",       7537,
	"Duna",      8264,
	"Ike",       12734,
	"Jool",      0,
	"Laythe",    6060,
	"Vall",      7975,
	"Bop",       21755,
	"Tylo",      12894,
	"Gilly",     6401,
	"Pol",       4889,
	"Dres",      5670,
	"Eeloo",     3795,
	"Sarnus",    0,
	"Hale",      5918,
	"Ovok",      14000,
	"Slate",     16398,
	"Tekto",     5873,
	"Urlum",     0,
	"Polta",     8649,
	"Priax",     30483,
	"Wal",       20773,
	"Tal",       11777,
	"Neidon",    0,
	"Thatmo",    4825,
	"Nissee",    8936,
	"Plock",     3330,
	"Karen",     4604,
	"Edas",      4943,
	"Vant",      19852,
	"Zore",      17726,
	"LintMikey", 1880,
	"Crokslev",  3700,
	"Geito",     661,
	"Havous",    66047,
	"Kal",       551,
	"KiKi",      16039,
	"Mracksis",  6373,
	"Flake",     246,
	"Ervo",      6880,
	"Archae",    4141,
	"Soden",     5188,
	"Lon",       2662
).

// Find root body
local rootBody is body.
until not rootBody:hasBody {
	set rootBody to rootBody:body.
}
if not MAX_TERRAIN_HEIGHTS:hasKey(rootBody:name) {
	MAX_TERRAIN_HEIGHTS:add(rootBody:name, 0).
}
// Add all orbiting bodies recursively
function addSatelliteBodies {
	parameter parentBody.
	for satelliteBody in parentBody:orbitingChildren {
		if not MAX_TERRAIN_HEIGHTS:hasKey(satelliteBody:name) {
			MAX_TERRAIN_HEIGHTS:add(satelliteBody:name, 0).
		}
		addSatelliteBodies(satelliteBody).
	}
}
addSatelliteBodies(rootBody).

global MAX_NAME_LENGTH is 0.
for b in MAX_TERRAIN_HEIGHTS:keys if b:length > MAX_NAME_LENGTH set MAX_NAME_LENGTH to b:length.

// Maximum angular surface spacing of the global terrain scan, in degrees.
global TERRAIN_SCAN_RESOLUTION is 0.25.
// Resolution used only around the highest point found by the global scan.
global TERRAIN_REFINE_RESOLUTION is 0.025.
// Percentage interval between terrain scan progress messages.
local TERRAIN_PROGRESS_INTERVAL is 1.
global TERRAIN_DATABASE_PATH is "0:/bodies.csv".

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

// This function will calculate the max terrain height of the specified body,
// and append "bodyName,maxTerrainHeight" to bodies.csv.
function calculateMaxTerrainHeight {
	parameter targetBodyQuery.

	local selectBodyResult is selectBody(targetBodyQuery).
	if not selectBodyResult:ok return selectBodyResult.

	local targetBody is selectBodyResult:val.
	local targetBodyName is targetBody:name.
	local maxTerrainHeight is 0.
	local maxLatitude is 0.
	local maxLongitude is 0.

	print "================================".
	print "Scanning terrain: " + targetBodyName.

	if targetBody:hasSolidSurface {
		// Allow a body whose entire surface is below its datum to return
		// its actual maximum rather than incorrectly returning zero.
		set maxTerrainHeight to -1e99.

		// Divide latitude exactly so both poles are included.
		local latitudeCount is ceiling(180 / TERRAIN_SCAN_RESOLUTION).
		local latitudeStep is 180 / latitudeCount.

		// Count the global samples before scanning so progress is based on
		// actual surface samples rather than latitude rows.
		local globalTotalSamples is 0.

		from { local latitudeIndex is 0. }
		until latitudeIndex > latitudeCount
		step { set latitudeIndex to latitudeIndex + 1. }
		do {
			local lat is -90 + latitudeIndex * latitudeStep.
			local latitudeScale is abs(cos(lat)).
			local longitudeCount is 1.

			if latitudeScale > 1e-9 {
				set longitudeCount to max(
					1,
					ceiling(360 * latitudeScale / TERRAIN_SCAN_RESOLUTION)
				).
			}

			set globalTotalSamples to globalTotalSamples + longitudeCount.
		}

		// The exact refinement size is not known until the coarse maximum
		// has been found. This is its maximum possible sample count, so
		// total progress during the global pass never overstates completion.
		local maxRefineAxisSamples is
			ceiling(
				2 * TERRAIN_SCAN_RESOLUTION
				/ TERRAIN_REFINE_RESOLUTION
			) + 1.
		local maximumRefineSamples is maxRefineAxisSamples^2.
		local estimatedTotalSamples is
			globalTotalSamples + maximumRefineSamples.

		local globalCompletedSamples is 0.
		local nextProgress is TERRAIN_PROGRESS_INTERVAL.

		print "Global scan: "
			+ globalTotalSamples
			+ " samples at <= "
			+ TERRAIN_SCAN_RESOLUTION
			+ " degrees".

		from { local latitudeIndex is 0. }
		until latitudeIndex > latitudeCount
		step { set latitudeIndex to latitudeIndex + 1. }
		do {
			local lat is -90 + latitudeIndex * latitudeStep.
			local latitudeScale is abs(cos(lat)).

			// Longitude degrees cover progressively less physical distance as
			// latitude approaches a pole. Reduce the number of samples there
			// while keeping approximately the same maximum surface spacing.
			local longitudeCount is 1.
			if latitudeScale > 1e-9 {
				set longitudeCount to max(
					1,
					ceiling(360 * latitudeScale / TERRAIN_SCAN_RESOLUTION)
				).
			}
			local longitudeStep is 360 / longitudeCount.

			from { local longitudeIndex is 0. }
			until longitudeIndex >= longitudeCount
			step { set longitudeIndex to longitudeIndex + 1. }
			do {
				local lng is -180 + longitudeIndex * longitudeStep.
				local terrainHeight is targetBody
					:geoPositionLatLng(lat, lng)
					:terrainHeight.

				if terrainHeight > maxTerrainHeight {
					set maxTerrainHeight to terrainHeight.
					set maxLatitude to lat.
					set maxLongitude to lng.
				}
			}

			set globalCompletedSamples to
				globalCompletedSamples + longitudeCount.

			local globalPercent is
				100 * globalCompletedSamples / globalTotalSamples.

			if globalPercent >= nextProgress {
				local totalPercent is
					100 * globalCompletedSamples / estimatedTotalSamples.

				print targetBodyName
					+ " global: "
					+ round(globalPercent, 1)
					+ "%; total: "
					+ round(totalPercent, 2)
					+ "%; max: "
					+ round(maxTerrainHeight, 1)
					+ " m".

				until nextProgress > globalPercent {
					set nextProgress to
						nextProgress + TERRAIN_PROGRESS_INTERVAL.
				}
			}
		}

		print "Global scan complete: "
			+ round(maxTerrainHeight, 3)
			+ " m at "
			+ round(maxLatitude, 4)
			+ ", "
			+ round(maxLongitude, 4).

		// Freeze the centre of the refinement. The maximum itself may move
		// during refinement, but that must not move the area being sampled.
		local refineCenterLatitude is maxLatitude.
		local refineCenterLongitude is maxLongitude.

		// Refine only the neighbourhood around the highest global sample.
		// The longitude window is expanded by 1/cos(latitude) so that the
		// refinement area represents roughly the same surface distance in
		// both dimensions, including at high latitudes.
		local refineLatitudeMin is max(
			-90,
			refineCenterLatitude - TERRAIN_SCAN_RESOLUTION
		).
		local refineLatitudeMax is min(
			90,
			refineCenterLatitude + TERRAIN_SCAN_RESOLUTION
		).
		local refineLatitudeCount is max(
			1,
			ceiling(
				(refineLatitudeMax - refineLatitudeMin)
					/ TERRAIN_REFINE_RESOLUTION
			)
		).
		local refineLatitudeStep is
			(refineLatitudeMax - refineLatitudeMin) / refineLatitudeCount.

		// Now that the refinement centre is known, calculate its exact
		// sample count so total progress can also be exact.
		local refineTotalSamples is 0.

		from { local latitudeIndex is 0. }
		until latitudeIndex > refineLatitudeCount
		step { set latitudeIndex to latitudeIndex + 1. }
		do {
			local lat is
				refineLatitudeMin + latitudeIndex * refineLatitudeStep.
			local latitudeScale is abs(cos(lat)).

			if latitudeScale <= 1e-9 {
				set refineTotalSamples to refineTotalSamples + 1.
			}
			else {
				local longitudeRadius is min(
					180,
					TERRAIN_SCAN_RESOLUTION / latitudeScale
				).
				local longitudeWidth is 2 * longitudeRadius.
				local refineLongitudeCount is max(
					1,
					ceiling(
						longitudeWidth * latitudeScale
							/ TERRAIN_REFINE_RESOLUTION
					)
				).

				// Refinement includes both ends of its interval.
				set refineTotalSamples to
					refineTotalSamples + refineLongitudeCount + 1.
			}
		}

		local totalSamples is globalTotalSamples + refineTotalSamples.
		local refineCompletedSamples is 0.
		set nextProgress to TERRAIN_PROGRESS_INTERVAL.

		print "Refining "
			+ refineTotalSamples
			+ " samples at <= "
			+ TERRAIN_REFINE_RESOLUTION
			+ " degrees".

		from { local latitudeIndex is 0. }
		until latitudeIndex > refineLatitudeCount
		step { set latitudeIndex to latitudeIndex + 1. }
		do {
			local lat is
				refineLatitudeMin + latitudeIndex * refineLatitudeStep.
			local latitudeScale is abs(cos(lat)).
			local rowSamples is 0.

			if latitudeScale <= 1e-9 {
				// All longitudes converge at the pole.
				local terrainHeight is targetBody
					:geoPositionLatLng(lat, refineCenterLongitude)
					:terrainHeight.

				if terrainHeight > maxTerrainHeight {
					set maxTerrainHeight to terrainHeight.
					set maxLatitude to lat.
					set maxLongitude to refineCenterLongitude.
				}

				set rowSamples to 1.
			}
			else {
				// Cover one coarse-grid spacing around the winning point,
				// measured as approximate physical angular distance.
				local longitudeRadius is min(
					180,
					TERRAIN_SCAN_RESOLUTION / latitudeScale
				).
				local longitudeWidth is 2 * longitudeRadius.
				local refineLongitudeCount is max(
					1,
					ceiling(
						longitudeWidth * latitudeScale
							/ TERRAIN_REFINE_RESOLUTION
					)
				).
				local refineLongitudeStep is
					longitudeWidth / refineLongitudeCount.

				from { local longitudeIndex is 0. }
				until longitudeIndex > refineLongitudeCount
				step { set longitudeIndex to longitudeIndex + 1. }
				do {
					local lng is mod(
						refineCenterLongitude - longitudeRadius
							+ longitudeIndex * refineLongitudeStep
							+ 180,
						360
					) - 180.

					local terrainHeight is targetBody
						:geoPositionLatLng(lat, lng)
						:terrainHeight.

					if terrainHeight > maxTerrainHeight {
						set maxTerrainHeight to terrainHeight.
						set maxLatitude to lat.
						set maxLongitude to lng.
					}
				}

				set rowSamples to refineLongitudeCount + 1.
			}

			set refineCompletedSamples to
				refineCompletedSamples + rowSamples.

			local refinePercent is
				100 * refineCompletedSamples / refineTotalSamples.

			if refinePercent >= nextProgress {
				local totalPercent is
					100 * (
						globalTotalSamples + refineCompletedSamples
					) / totalSamples.

				print targetBodyName
					+ " refine: "
					+ round(refinePercent, 1)
					+ "%; total: "
					+ round(totalPercent, 2)
					+ "%; max: "
					+ round(maxTerrainHeight, 1)
					+ " m".

				until nextProgress > refinePercent {
					set nextProgress to
						nextProgress + TERRAIN_PROGRESS_INTERVAL.
				}
			}
		}
	}
	else {
		print targetBodyName + " has no solid surface; using 0 m".
	}

	log (char(34) + targetBodyName + char(34) + ","):padright(MAX_NAME_LENGTH + 4) + maxTerrainHeight + ","
		to TERRAIN_DATABASE_PATH.

	print targetBodyName
		+ " complete: 100%; max terrain = "
		+ round(maxTerrainHeight, 3)
		+ " m at "
		+ round(maxLatitude, 4)
		+ ", "
		+ round(maxLongitude, 4).

	return ApiOK(true).
}

set config:ipu to 2000.

local resuming is core:tag <> "".
local skipping is true.
for bodyName in MAX_TERRAIN_HEIGHTS:keys {
	if MAX_TERRAIN_HEIGHTS[bodyName] = 0 {
		if not resuming and not skipping {
			set core:tag to bodyName.
			kuniverse:quicksave().
		}
		if not resuming or not skipping or bodyName = core:tag {
			calculateMaxTerrainHeight(bodyName).
			set skipping to false.
			set resuming to false.
		}
	}
}
print "Script Complete".