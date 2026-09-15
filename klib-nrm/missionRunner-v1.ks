{
	local STATE_FILE is "1:/state.run".
	local STATE_TMP is "1:/state.tmp".
	local _IsRunnerFinished is{
		parameter runnerState.
		return runnerState:steps:length=0 or runnerState:currentStep>=runnerState:steps:length.
	}.
	local _ExecuteEventLoop is{
		parameter runnerState,eventInterface.
		local enabled is list().
		for event in runnerState:events:values if event:enabled enabled:add(event).
		for event in enabled event:invoke(eventInterface).
	}.
	local _SetEventState is{
		parameter runnerState,eventName,enabled.
		if not runnerState:events:haskey(eventName)return false.
		set runnerState:events[eventName]:enabled to enabled.
		return true.
	}.
	local _SaveState is{
		parameter runnerState.
		local stateList is list(runnerState:currentStep,runnerState:nextStep).
		local events is runnerState:events.
		for eventName in events:keys if events[eventName]:enabled<>events[eventName]:default stateList:add(eventName).
		local stateData is stateList:join(",").
		if exists(STATE_TMP)deletePath(STATE_TMP).
		local hFile is create(STATE_TMP).
		if volume(1):freespace<stateData:length or not hFile:write(stateData)dmsg("[MissionRunner] WARNING! Insufficient volume space or write error! Mission state is not saved!",true).
		else movePath(STATE_TMP,STATE_FILE).
		if exists(STATE_TMP)deletePath(STATE_TMP).
	}.
	local _InvalidKeyName is{
		parameter name.
		return not name:matchesPattern("^[\w-]+$").
	}.
	local _StepNameExists is{
		parameter steps,stepName.
		for entry in steps if entry:name=stepName return true.
		return false.
	}.
	export(lex("create",{
		parameter constructorSteps is list().
		local runnerState is lex("steps",list(),"events",lex(),"commands",lex(),"currentStep",0,"nextStep",1,"errors",list(),"started",false).
		local runnerInterface is lex(
			"next",{
				set runnerState:currentStep to runnerState:nextStep.
				set runnerState:nextStep to runnerState:nextStep+1.
				_SaveState(runnerState).
			},
			"end",{
				set runnerState:currentStep to runnerState:steps:length.
				set runnerState:nextStep to runnerState:steps:length+1.
				_SaveState(runnerState).
			},
			"disable",{
				parameter eventName.
				if _SetEventState(runnerState,eventName,false){
					_SaveState(runnerState).
					return ApiOK().
				}
				return ApiFail("Event not found: "+eventName).
			},
			"enable",{
				parameter eventName.
				if _SetEventState(runnerState,eventName,true){
					_SaveState(runnerState).
					return ApiOK().
				}
				return ApiFail("Event not found: "+eventName).
			},
			"current",{
				if _IsRunnerFinished(runnerState)return "Ended".
				local currentStep is runnerState:steps[runnerState:currentStep].
				if runnerState:started return currentStep:name.
				return "Starting/"+currentStep:name.
			}
		).
		local eventInterface is lex(
			"enable",runnerInterface:enable,
			"disable",runnerInterface:disable,
			"current",runnerInterface:current
		).
		runnerInterface:add("invoke",{
			parameter commandName.
			if runnerState:commands:haskey(commandName)return ApiOK(runnerState:commands[commandName](eventInterface)).
			return ApiFail("Command not found: "+commandName).
		}).
		runnerInterface:add("tick",{
			_ExecuteEventLoop(runnerState,eventInterface).
		}).
		eventInterface:add("invoke",runnerInterface:invoke).
		local runnerInstance is lex().
		runnerInstance:add("steps",{
			parameter newSteps.
			for entry in newSteps{
				local name is entry[0].
				if _InvalidKeyName(name)runnerState:errors:add("Mission step '"+name+"' has invalid characters").
				else if name="Starting" or name="Ended" runnerState:errors:add("Mission step '"+name+"' is reserved").
				else if _StepNameExists(runnerState:steps,name)runnerState:errors:add("Mission step '"+name+"' already exists").
				else runnerState:steps:add(lex("name",name,"run",entry[1])).
			}
			return runnerInstance.
		}).
		runnerInstance:add("events",{
			parameter newEvents.
			for entry in newEvents{
				local name is entry[0].
				local enabled is choose entry[2]if entry:length>2 else true.
				if _InvalidKeyName(name)runnerState:errors:add("Mission event '"+name+"' has invalid characters").
				else if runnerState:events:haskey(name)runnerState:errors:add("Mission event '"+name+"' already exists").
				else runnerState:events:add(name,lex("enabled",enabled,"default",enabled,"invoke",entry[1])).
			}
			return runnerInstance.
		}).
		runnerInstance:add("commands",{
			parameter newCommands.
			for entry in newCommands{
				local name is entry[0].
				if _InvalidKeyName(name)runnerState:errors:add("Mission command '"+name+"' has invalid characters").
				else if runnerState:commands:haskey(name)runnerState:errors:add("Mission command '"+name+"' already exists").
				else runnerState:commands:add(name,entry[1]).
			}
			return runnerInstance.
		}).
		runnerInstance:add("start",{
			if exists(STATE_FILE){
				local stateList is open(STATE_FILE):readall:string:split(",").
				if stateList:length<2 runnerState:errors:add("Saved mission state is malformed").
				else {
					set runnerState:currentStep to stateList[0]:toscalar(-1).
					set runnerState:nextStep to stateList[1]:toscalar(-1).
					if runnerState:currentStep=-1 or runnerState:nextStep=-1{
						set runnerState:currentStep to-1.
						set runnerState:nextStep to-1.
						runnerState:errors:add("Failed to load current/next step from saved state").
					}
					for eventName in stateList:sublist(2,stateList:length-2)
						if runnerState:events:haskey(eventName)_SetEventState(runnerState,eventName,not runnerState:events[eventName]:default).
						else dmsg("[MissionRunner] WARNING! Attempted to restore state for mission event: "+eventName,true).
				}
			}
			if runnerState:errors:length>0{
				notify("Mission failed to start").
				dmsg("[MissionRunner] Mission cannot start due to one or more errors:",true).
				for error in runnerState:errors dmsg(" * "+error,true).
				return false.
			}
			set runnerState:started to true.
			until _IsRunnerFinished(runnerState){
				runnerState:steps[runnerState:currentStep]:run(runnerInterface).
				_ExecuteEventLoop(runnerState,eventInterface).
				wait 0.
			}
			return true.
		}).
		runnerInstance:steps(constructorSteps).
		return runnerInstance.
	})).
}