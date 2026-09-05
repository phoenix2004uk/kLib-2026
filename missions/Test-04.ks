local ascent is import("prg/atmosphericAscent-v2").
local executeNode is import("prg/executeNode-v1").
local circularize is import("mnv/circularizeAtAp-v1").
local steeringSystem is import("sys/steering-v1").
local steeringSettled is steeringSystem:isSettled.
clearScreen.

// Mission Configuration
local launchApoapsis is 100e3.
local launchInclination is 0.

local test_minVerticalSpeedStart is 50.
local test_minVerticalSpeedEnd is 50.
local test_minVerticalSpeedStep is 10.

local test_throttleControlSpeedStart is 250.
local test_throttleControlSpeedEnd is 250.
local test_throttleControlSpeedStep is 5.

local TEST_STATE_PATH is "0:/ascentTest-state.json".

local test_minVerticalSpeedCount is floor((test_minVerticalSpeedEnd - test_minVerticalSpeedStart) / test_minVerticalSpeedStep) + 1.
local test_throttleControlSpeedCount is floor((test_throttleControlSpeedEnd - test_throttleControlSpeedStart) / test_throttleControlSpeedStep) + 1.
local testCount is test_minVerticalSpeedCount * test_throttleControlSpeedCount.

local testIndex is 0.
local test_minVerticalSpeed is test_minVerticalSpeedStart.
local test_throttleControlSpeed is test_throttleControlSpeedStart.

{
	// Mission Overview
	preTestSetup().
	prelaunch().
	kerbinLaunch(launchApoapsis, launchInclination).
	kerbinCircularization().
	postTestCleanup().

	function setTestConfig {
		parameter index.

		local minVerticalSpeedIndex is floor(index / test_throttleControlSpeedCount).
		local throttleControlSpeedIndex is mod(index, test_throttleControlSpeedCount).

		set test_minVerticalSpeed to test_minVerticalSpeedStart + minVerticalSpeedIndex * test_minVerticalSpeedStep.
		set test_throttleControlSpeed to test_throttleControlSpeedStart + throttleControlSpeedIndex * test_throttleControlSpeedStep.
	}

	function saveTestState {
		if exists(TEST_STATE_PATH) {
			deletepath(TEST_STATE_PATH).
		}

		writejson(
			lex(
				"testIndex", testIndex,
				"minVerticalSpeed", test_minVerticalSpeed,
				"throttleControlSpeed", test_throttleControlSpeed
			),
			TEST_STATE_PATH
		).
	}

	function preTestSetup {
		if exists(TEST_STATE_PATH) {
			local testState is readjson(TEST_STATE_PATH).

			set testIndex to testState["testIndex"].
			set test_minVerticalSpeed to testState["minVerticalSpeed"].
			set test_throttleControlSpeed to testState["throttleControlSpeed"].
		} else {
			set testIndex to 0.
			setTestConfig(testIndex).
			saveTestState().
		}

		// A result log means this test finished, but KSP may have
		// crashed before the state file advanced.
		until testIndex >= testCount or not exists("0:/dmsg/ascentTest-" + testIndex + ".log") {
			set testIndex to testIndex + 1.

			if testIndex < testCount {
				setTestConfig(testIndex).
				saveTestState().
			}
		}

		if testIndex >= testCount {
			print "Ascent test matrix complete.".
			shutdown.
		}

		// Remove any partial log left by a crash during this test.
		local currentLogPath is
			"0:/dmsg/" + core:part:uid + "-" + ship:name + ".log".

		if exists(currentLogPath) {
			deletepath(currentLogPath).
		}

		dmsg(
			"Ascent test " + testIndex
			+ "; minVerticalSpeed=" + test_minVerticalSpeed
			+ "; throttleControlSpeed=" + test_throttleControlSpeed,
			true
		).
	}

	function currentIsp {
		list engines in engineList.
		local totalThrust is 0.
		local totalFlow is 0.

		for en in engineList {
			if en:ignition and not en:flameout {
				set totalThrust to totalThrust + en:availableThrust.
				set totalFlow to totalFlow + en:availableThrust / en:isp.
			}
		}

		if totalFlow = 0 return 0.
		return totalThrust / totalFlow.
	}

	function currentStageDeltaV {
		local isp is currentIsp().
		if isp = 0 return 0.

		local propellantMass is 0.
		local resources is stage:resources.

		for resource in resources {
			if resource:name = "LiquidFuel"
			or resource:name = "Oxidizer" {
				set propellantMass to
					propellantMass
					+ resource:amount * resource:density.
			}
		}

		local finalMass is ship:mass - propellantMass.
		if finalMass <= 0 return 0.

		return 9.80665 * isp * ln(ship:mass / finalMass).
	}

	function postTestCleanup {
		local remainingDeltaV is currentStageDeltaV().

		dmsg(
			"Ascent test result"
			+ "; testIndex=" + testIndex
			+ "; minVerticalSpeed=" + test_minVerticalSpeed
			+ "; throttleControlSpeed=" + test_throttleControlSpeed
			+ "; remainingDeltaV=" + round(remainingDeltaV, 1)
		).

		local currentLogPath is "0:/dmsg/" + core:part:uid + "-" + ship:name + ".log".
		local resultLogPath is "0:/dmsg/" + ship:name + " ascentTest-" + testIndex + ".log".

		movepath(currentLogPath, resultLogPath).

		// There is nothing to revert into after the final result.
		if testIndex + 1 >= testCount {
			print "Ascent test matrix complete.".
			shutdown.
		}

		set testIndex to testIndex + 1.
		setTestConfig(testIndex).
		saveTestState().

		kuniverse:revertToLaunch().
	}

	// Mission Steps
	function prelaunch {
		dmsg("Launching in 3 seconds", true).
		lights on.
		wait 3.
	}

	function kerbinLaunch {
		parameter launchApoapsis, launchInclination is 0.

		ascent:executeAscent(
			launchApoapsis,
			launchInclination,
			80,
			test_minVerticalSpeed,
			test_throttleControlSpeed
		).
		ascent:orbitalInsertion(launchApoapsis).
	}

	function kerbinCircularization {
		local circularizeResult is circularize().
		if not circularizeResult:ok {
			dmsg("Failed to plan maneuver", true).
			shutdown.
		}

		rcs on.
		add circularizeResult:val.
		if steeringSettled() executeNode:warpToNode(60).
		executeNode:executeNode(60).
		rcs off.
	}
}