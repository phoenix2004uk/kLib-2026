// ============================================================================
// Mission Runner v1
// Persistent sequential mission executor with polled events and named commands.
//
// Steps execute sequentially and are generally non-blocking: Each step handler is repeatedly called until it uses `next()` or `end()` from the provided interface to advance/end the mission.
// Enabled events are run after each time a step handler is called, regardless if that step uses `next()`.
// Event state changes (enable / disable) apply on the next event-loop.
// Steps can use blocking loops or scripts, and the `tick()` function is provided to optionally run the event-loop without yielding back to the mission runner.
// Mission progress and non-default event states (enabled/disabled) persist across KPU restarts.
//
// Persistent state does support updated mission scripts, as the mission runner state will restore the same *numerical* step/next positions.
// This allows current/future steps to be added/moved/removed, but inserting/removing earlier steps can cause desyncronization of mission progress so Kare* must be taken.
// Events can be removed or renamed with an updated script without issue with the persisted state.
// *Kare: By ensuring steps, status and persistence remain synchronized, or by using the internal knowledge of the mission runner to force a mission back into coherance ;)
// ============================================================================
//
// Usage allows chained-functions for configuration and starting:
//   import("missionRunner-v1")
//     :create(steps)
//     :events(events)
//     :commands(commands)
//     :start().
//
// Or configure and start separately:
//   local missionRunner is import("missionRunner-v1"):create().
//   missionRunner:steps(steps).
//   missionRunner:events(events).
//   missionRunner:commands(commands).
//   missionRunner:start().
//
// ============================================================================
// Configuration:
//   `create([steps])`		Optionally add steps on import creation (see below).
//   `steps(steps)`			Add mission steps as a list of `list(name, handler)`.
//   `events(events)`		Add events for the event-loop as a list of `list(name, handler [, enabled=true])`, where the 3rd `enabled` parameter is the default enabled state (true by default).
//   `commands(commands)`	Add utility commands as a list of `list(name, handler)`, these can be called within a step/event/command via the passed interface object `:invoke(name)`.
//							Note: commands do not currently support arguments.
//   `start()`				Begins (or resumes) the mission sequence.
//
//   Note: Step/Event/Command names must be unique within their own type, and may contain only alphanumeric characters, underscores or hyphens. "Ended" and "Starting" are reserved step names.
// ============================================================================
// Handler interfaces:
//   Step interface - passed to every step handler and contains: next(), end(), enable(name), disable(name), current(), invoke(name), tick()
//   Event interface - passed to every event handler and contains: enable(name), disable(name), current(), invoke(name)
//   Command interface - passed to every command handler and contains: enable(name), disable(name), current(), invoke(name)
// Interface functions:
//   next()					Advance the mission to the next mission step in sequence.
//   end()					End the mission by advancing to the end of the mission sequence. The event-loop is allowed to run a final time.
//   enable(name)			Enable the named event*.
//   disable(name)			Disable the named event*.
//   current()				Returns the name of the current step. "Starting/<name>" is returned if the mission loop has not started, and "Ended" is returned if the mission has ended (or there are no steps).
//   invoke(name)			Invoke the named command.
//   tick()					Invoke the mission event-loop immediately without yielding control back to the mission runner. The event-loop will still run once the step handler yields control back to the mission runner.
//							* Enabling or disabling events will take effect for the following event-loop.
// ============================================================================
{
	// TODO: later enhancement could allow nested mission runners, at which point the state filename must become dynamic from the runner, with only the root runner being a static filename
	local STATE_FILE is "1:/state.run".
	local STATE_TMP is "1:/state.tmp".
	local STARTING_STEP is "Starting".
	local ENDED_STEP is "Ended".

	function _IsRunnerFinished {
		parameter runnerState.
		return runnerState:steps:length = 0 or runnerState:currentStep >= runnerState:steps:length.
	}
	function _ExecuteEventLoop {
		parameter runnerState, eventInterface.

		local events is runnerState:events.
		local enabled is list().
		// snapshot enabled events, any changes will not take effect until the next event loop
		for event in events:values {
			if event:enabled enabled:add(event).
		}
		for event in enabled {
			event:invoke(eventInterface).
		}
	}
	function _SetEventState {
		parameter runnerState, eventName, enabled.

		if not runnerState:events:haskey(eventName) return false.
		set runnerState:events[eventName]:enabled to enabled.
		return true.
	}

	function _ClearTempState {
		if exists(STATE_TMP) deletePath(STATE_TMP).
	}
	// state will be conservatively saved in the form: currentStep,nextStep,eventName,eventName,...
	// where events are stored if their enabled state is not their default state
	// this will be smaller than saving a json object
	function _SaveState {
		parameter runnerState.
		
		local stateList is list(
			runnerState:currentStep,
			runnerState:nextStep
		).

		local events is runnerState:events.
		for eventName in events:keys {
			if events[eventName]:enabled <> events[eventName]:default stateList:add(eventName).
		}

		local stateData is stateList:join(",").

		_ClearTempState().
		local hFile is create(STATE_TMP).
		if volume(1):freespace < stateData:length or not hFile:write(stateData) {
			dmsg("[MissionRunner] WARNING! Insufficient volume space or write error! Mission state is not saved!", true).
		}
		else {
			movePath(STATE_TMP, STATE_FILE). // kOS over-writes any existing file
		}
		_ClearTempState().
	}
	function _LoadState {
		parameter runnerState.

		if not exists(STATE_FILE) return.

		local hFile is open(STATE_FILE).
		local stateData is hFile:readall:string.
		local stateList is stateData:split(",").

		if stateList:length < 2 {
			runnerState:errors:add("Saved mission state is malformed").
			return.
		}

		// check that current/next step are numbers
		set runnerState:currentStep to stateList[0]:toscalar(-1).
		set runnerState:nextStep to stateList[1]:toscalar(-1).
		if runnerState:currentStep = -1 or runnerState:nextStep = -1 {
			set runnerState:currentStep to -1.
			set runnerState:nextStep to -1.
			runnerState:errors:add("Failed to load current/next step from saved state").
		}

		local events is runnerState:events.
		for eventName in stateList:sublist(2, stateList:length - 2) {
			if events:haskey(eventName) {
				_SetEventState(runnerState, eventName, not events[eventName]:default).
			}
			else {
				dmsg("[MissionRunner] WARNING! Attempted to restore state for mission event: " + eventName, true).
			}
		}
	}

	function _InvalidKeyName {
		parameter name.
		return not name:matchesPattern("^[\w-]+$").
	}
	function instanceStart {
		parameter runnerState, runnerInterface, eventInterface.

		_LoadState(runnerState).

		local errors is runnerState:errors.
		if errors:length > 0 {
			notify("Mission failed to start").
			dmsg("[MissionRunner] Mission cannot start due to one or more errors:", true).
			for error in errors {
				dmsg(" * " + error, true).
			}
			return false.
		}

		set runnerState:started to true.

		until _IsRunnerFinished(runnerState) {
			local currentStep is runnerState:steps[runnerState:currentStep].
			currentStep:run(runnerInterface).

			// the event loop is allowed to run one last time after the final step
			_ExecuteEventLoop(runnerState, eventInterface).

			wait 0.
		}
		return true.
	}
	function _StepNameReserved {
		parameter stepName.
		return stepName = STARTING_STEP or stepName = ENDED_STEP.
	}
	function _StepNameExists {
		parameter steps, stepName.
		for entry in steps {
			if entry:name = stepName return true.
		}
		return false.
	}
	function instanceAddSteps {
		parameter runnerState, runnerInstance, newSteps.

		local currentSteps is runnerState:steps.
		for entry in newSteps {
			local name is entry[0].
			local handler is entry[1].
			if _InvalidKeyName(name) {
				runnerState:errors:add("Mission step '" + name + "' has invalid characters").
			}
			else if _StepNameReserved(name) {
				runnerState:errors:add("Mission step '" + name + "' is reserved").
			}
			else if _StepNameExists(currentSteps, name) {
				runnerState:errors:add("Mission step '" + name + "' already exists").
			}
			else {
				currentSteps:add(lex(
					"name", name,
					"run", handler
				)).
			}
		}
		return runnerInstance.
	}
	function _EventNameExists {
		parameter events, eventName.
		return events:haskey(eventName).
	}
	function instanceAddEvents {
		parameter runnerState, runnerInstance, newEvents.

		local currentEvents is runnerState:events.
		for entry in newEvents {
			local name is entry[0].
			local handler is entry[1].
			local enabled is choose entry[2] if entry:length > 2 else true.
			if _InvalidKeyName(name) {
				runnerState:errors:add("Mission event '" + name + "' has invalid characters").
			}
			else if _EventNameExists(currentEvents, name) {
				runnerState:errors:add("Mission event '" + name + "' already exists").
			}
			else {
				currentEvents:add(name, lex(
					"enabled", enabled,
					"default", enabled,
					"invoke", handler
				)).
			}
		}
		return runnerInstance.
	}
	function _CommandNameExists {
		parameter commands, commandName.
		return commands:haskey(commandName).
	}
	function instanceAddCommands {
		parameter runnerState, runnerInstance, newCommands.

		local currentCommands is runnerState:commands.
		for entry in newCommands {
			local name is entry[0].
			local handler is entry[1].
			if _InvalidKeyName(name) {
				runnerState:errors:add("Mission command '" + name + "' has invalid characters").
			}
			else if _CommandNameExists(currentCommands, name) {
				runnerState:errors:add("Mission command '" + name + "' already exists").
			}
			else {
				currentCommands:add(name, handler).
			}
		}
		return runnerInstance.
	}

	function interfaceAdvanceStep {
		parameter runnerState.

		set runnerState:currentStep to runnerState:nextStep.
		set runnerState:nextStep to runnerState:nextStep + 1.
		_SaveState(runnerState).
	}
	function interfaceTerminate {
		parameter runnerState.

		set runnerState:currentStep to runnerState:steps:length.
		set runnerState:nextStep to runnerState:steps:length + 1.
		_SaveState(runnerState).
	}
	function interfaceDisableEvent {
		parameter runnerState, eventName.

		if _SetEventState(runnerState, eventName, false) {
			_SaveState(runnerState).
			return ApiOK().
		}
		return ApiFail("Event not found: " + eventName).
	}
	function interfaceEnableEvent {
		parameter runnerState, eventName.

		if _SetEventState(runnerState, eventName, true) {
			_SaveState(runnerState).
			return ApiOK().
		}
		return ApiFail("Event not found: " + eventName).
	}
	// returns the name of the current step
	// if mission has ended, then returns `ENDED_STEP`
	// if mission has not started the main loop, then returns `STARTING_STEP / <currentStep:name>`
	function interfaceCurrentStepName {
		parameter runnerState.

		if _IsRunnerFinished(runnerState) {
			return ENDED_STEP.
		}

		local currentStep is runnerState:steps[runnerState:currentStep].
		if runnerState:started {
			return currentStep:name.
		}

		return STARTING_STEP + "/" + currentStep:name.
	}
	function interfaceInvokeCommand {
		parameter runnerState, commandInterface, commandName.
		
		if not runnerState:commands:haskey(commandName) return ApiFail("Command not found: " + commandName).

		local command is runnerState:commands[commandName].
		return ApiOK(command(commandInterface)).
	}
	function interfaceTick {
		parameter runnerState, eventInterface.

		_ExecuteEventLoop(runnerState, eventInterface).
		// no `wait 0`, as a calling blocking loop should have its own wait policy
	}

	function createMissionRunner {
		parameter constructorSteps is list().

		// this is the internal private state of the mission
		local runnerState is lex(
			"steps", list(),
			"events", lex(),
			"commands", lex(),
			"currentStep", 0,
			"nextStep", 1,
			"errors", list(),
			"started", false
		).

		// This `runnerInterface` is passed as the first parameter to every step, with `eventInterface` and `commandInterface` for every event and command respectively
		local runnerInterface is lex(
			"next", interfaceAdvanceStep@:bind(runnerState), // advance to the next step
			"end", interfaceTerminate@:bind(runnerState), // end the mission
			"disable", interfaceDisableEvent@:bind(runnerState), // disable an event in the main loop
			"enable", interfaceEnableEvent@:bind(runnerState), // enable an event in the main loop
			"current", interfaceCurrentStepName@:bind(runnerState) // returns the name of the current step
		).
		local eventInterface is lex(
			"enable", runnerInterface:enable,
			"disable", runnerInterface:disable,
			"current", runnerInterface:current
		).
		local commandInterface is eventInterface. // place-holder if we want to separate the event and command interfaces; this would be normalized/minified out

		runnerInterface:add("invoke", interfaceInvokeCommand@:bind(runnerState, commandInterface)). // invoke a named command
		runnerInterface:add("tick", interfaceTick@:bind(runnerState, eventInterface)). // allow a blocking loop within a step, to run the mission event loop via this callback

		eventInterface:add("invoke", runnerInterface:invoke).

		// this is returned from `create` to setup the mission runner
		local runnerInstance is lex().
		runnerInstance:add("steps", instanceAddSteps@:bind(runnerState, runnerInstance)). // for adding steps
		runnerInstance:add("events", instanceAddEvents@:bind(runnerState, runnerInstance)). // for adding events
		runnerInstance:add("commands", instanceAddCommands@:bind(runnerState, runnerInstance)). // for adding commands
		runnerInstance:add("start", instanceStart@:bind(runnerState, runnerInterface, eventInterface)). // start the mission runner

		// add any steps provided to `create`
		runnerInstance:steps(constructorSteps).

		return runnerInstance.
	}
	export(lex("create", createMissionRunner@)).
}

// EXAMPLE USAGE

// // Mission Parameters
// local launchApoapsis is 100e3.
// local launchInclination is 0.

// // regular klib imports
// local rt is import("sys/remoteTech-v1").

// // use import() for common steps
// local ascent is import("prg/atmosphericAscent-v2").
// local orbitalInsertion is import("op/orbitalInsertion-v1").
// local mnvCircularize is import("mnv/circularizeAtApsis-v1").

// // import, create and start the mission runner via function chaining
// import("missionRunner-v1")
// :create(list(
// 	list("prelaunch", {
// 		parameter runner.
// 		runner:next().
// 	}),
// 	list("launch", {
// 		parameter runner.
// 		ascent:executeAscent(launchApoapsis, launchInclination, runner:tick). // the internal blocking loop can now call the tick() function to execute the event loop
// 		runner:next().
// 	}), // steps can be "blocking", which means the mission loop is not running until the step completes via `runner:next()`
// 	list("orbitalInsertion", orbitalInsertion),
// 	list("circularize", {
// 		parameter runner.

// 		mnvCircularize:Ap().
// 		runner:next().
// 	}),
// 	list("executeNode", {
// 		parameter runner.
// 	})
// ))
// :events(list( // all event functions will run continuously in the background of the mission, so these should most do a cheap check to invoke something
// 	list("low-power", {
// 		parameter events.
// 		for res in ship:resources {
// 			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity < 0.3 {
// 				// we can disable and enable events, so that it acts similar to a state machine and prevents running excess event code in the main loop
// 				// when toggling opposing events, always enable the replacement before disabling the current
// 				events:enable("high-power").
// 				events:disable("low-power").
// 				events:invoke("comms-off").
// 				break.
// 			}
// 		}
// 	}),
// 	list("high-power", {
// 		parameter events.
// 		for res in ship:resources {
// 			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity > 0.6 {
// 				// when toggling opposing events, always enable the replacement before disabling the current
// 				events:enable("low-power").
// 				events:disable("high-power").
// 				events:invoke("comms-on").
// 				break.
// 			}
// 		}
// 	}, false)
// ))
// :commands(list( // commands can be called by steps or events, and are really just functions you would otherwise call anywhere in a regular mission script
// 	list("comms-on", {
// 		parameter commands.

// 		notify("Deploying communication dish").
// 		for dish in rt:getAllDish() {
// 			dish:enable().
// 			dish:setTarget(Kerbin).
// 		}
// 	}),
// 	list("comms-off", {
// 		parameter commands.

// 		notify("Communication disabled").
// 		for dish in rt:getAllDish() {
// 			dish:disable().
// 		}
// 	}),
// 	list("do-science", {
// 		parameter commands.

// 		// do some science!
// 	})
// ))
// :start().