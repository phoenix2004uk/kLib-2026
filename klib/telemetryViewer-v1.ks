// ============================================================================
// Telemetry Viewer v1
// Stateful telemetry screen registry and non-blocking terminal renderer.
//
// A screen definition is a lexicon containing:
//   label  - short tab label
//   title  - optional screen heading (defaults to label)
//   fields - optional list of list(label, valueDelegate [, formatter])
//            or "-" entries for horizontal separators
//
// Built-in formatters:
//   auto, text, or any suffix of `util/format`
// The formatter may also be a delegate taking the raw field value and returning
// the rendered value.
//
// Interface returned by create():
//   screen(name, definition) Add one screen definition.
//   fields(name, fields)     Add fields to an existing screen.
//   remove(name)             Remove a loaded screen.
//   show(name)               Select a loaded screen.
//   has(name)                True if a screen is loaded.
//   current()                Stable name of the selected screen, or "".
//   redraw()                 Force a full redraw on the next tick.
//   tick()                   Process terminal input and render one frame.
//
// tick() does not WAIT and owns no loop; the telemetry processor script controls
// refresh cadence and inter-processor messaging.
// ============================================================================
{
	local printLn is import("util/printLn-v1"):printLn.
	local format is import("util/format-v1").

	local MAX_SCALAR_DECIMALS is 4.

	// ============================================================================
	// Formatting helpers
	// ============================================================================

	function _RepeatChar {
		parameter ch, count.

		local text is "".
		until text:length >= count set text to text + ch.
		return text.
	}

	function _ValidFormatter {
		parameter formatter.

		return formatter:isType("KOSDelegate")
			or (
				formatter:isType("String")
				and (
					formatter = "auto"
					or formatter = "text"
					or format:hasKey(formatter)
				)
			).
	}

	function _FormatFieldValue {
		parameter rawValue, formatter.

		if formatter:isType("KOSDelegate") {
			return formatter(rawValue):toString.
		}

		if rawValue:isType("List") and (formatter = "auto" or format:hasKey(formatter)) {
			local values is list().
			for value in rawValue {
				values:add(_FormatFieldValue(value, formatter)).
			}
			return values:join(" / ").
		}

		if formatter = "text" or not rawValue:isType("Scalar") {
			return rawValue:toString.
		}
		if format:hasKey(formatter) {
			return format[formatter](rawValue).
		}
		return round(rawValue, MAX_SCALAR_DECIMALS):toString.
	}

	// ============================================================================
	// Private screen-definition helpers
	// ============================================================================

	function _FindScreenIndex {
		parameter viewerState, screenName.

		for screenIndex in range(viewerState:screens:length) {
			if viewerState:screens[screenIndex]:name = screenName {
				return screenIndex.
			}
		}
		return -1.
	}

	function _BuildFields {
		parameter fieldDefinitions.

		local parsedFields is list().
		local fieldWidth is 0.

		for fieldDefinition in fieldDefinitions {
			if fieldDefinition:isType("String") {
				if fieldDefinition = "-" {
					parsedFields:add(fieldDefinition).
				}
				else {
					return ApiFail("Telemetry field string must be '-' for a line break").
				}
			}
			else if fieldDefinition:isType("List") {
				if fieldDefinition:length < 2 {
					return ApiFail("Telemetry field definition must contain a label and value delegate").
				}

				local fieldLabel is fieldDefinition[0]:toString.
				local formatter is choose fieldDefinition[2] if fieldDefinition:length > 2 else "auto".

				if not _ValidFormatter(formatter) {
					return ApiFail("Telemetry field '" + fieldLabel + "' has an invalid formatter").
				}

				parsedFields:add(lex(
					"label", fieldLabel,
					"read", fieldDefinition[1],
					"formatter", formatter
				)).
				set fieldWidth to max(fieldWidth, fieldLabel:length).
			}
		}

		return ApiOK(lex(
			"fields", parsedFields,
			"fieldWidth", fieldWidth
		)).
	}

	function _BuildScreen {
		parameter viewerState, screenName, screenDefinition.

		if _FindScreenIndex(viewerState, screenName) >= 0 {
			return ApiFail("Telemetry screen '" + screenName + "' is already loaded").
		}
		if not screenDefinition:hasKey("label") {
			return ApiFail("Telemetry screen '" + screenName + "' is missing a label").
		}

		local screenLabel is screenDefinition:label:toString.
		local screenTitle is choose screenDefinition:title:toString if screenDefinition:hasKey("title") else screenLabel.
		local fieldDefinitions is choose screenDefinition:fields if screenDefinition:hasKey("fields") else list().
		local fieldsResult is _BuildFields(fieldDefinitions).
		if not fieldsResult:ok return fieldsResult.

		return ApiOK(lex(
			"name", screenName,
			"label", screenLabel,
			"title", screenTitle,
			"fields", fieldsResult:val:fields,
			"fieldWidth", fieldsResult:val:fieldWidth
		)).
	}

	// ============================================================================
	// Private layout / rendering
	// ============================================================================

	function _RecalculateLayout {
		parameter viewerState.

		local screens is viewerState:screens.
		local headerWidth is choose 0 if screens:length = 0 else 6 + (screens:length - 1) * 3.
		local staticWidth is 0.
		local requiredHeight is 3.

		for screenDefinition in screens {
			set headerWidth to headerWidth + screenDefinition:label:length + 6.
			set staticWidth to max(
				staticWidth,
				max(screenDefinition:title:length + 2, screenDefinition:fieldWidth + 2)
			).
			set requiredHeight to max(requiredHeight, 3 + screenDefinition:fields:length).
		}

		set viewerState:layoutWidth to max(headerWidth, staticWidth).
		set viewerState:layoutHeight to requiredHeight.
		set viewerState:dirty to true.
	}

	function _EnsureTerminalSize {
		parameter viewerState, frameWidth is 0.

		set viewerState:contentWidth to max(viewerState:contentWidth, frameWidth).

		local requiredWidth is max(
			viewerState:minWidth,
			max(viewerState:layoutWidth, viewerState:contentWidth)
		).
		local requiredHeight is max(viewerState:minHeight, viewerState:layoutHeight).

		if terminal:width < requiredWidth {
			set terminal:width to requiredWidth.
			set viewerState:dirty to true.
		}
		if terminal:height < requiredHeight {
			set terminal:height to requiredHeight.
			set viewerState:dirty to true.
		}
	}

	function _RenderHeader {
		parameter viewerState.

		local headerTabs is list().
		local headerUnderlines is list().

		for screenDefinition in viewerState:screens {
			local screenLabel is screenDefinition:label.
			if screenDefinition:name = viewerState:activeScreen {
				headerTabs:add("[► " + screenLabel + " ◄]").
				headerUnderlines:add(" " + _RepeatChar("=", screenLabel:length + 4) + " ").
			}
			else {
				headerTabs:add("[  " + screenLabel + "  ]").
				headerUnderlines:add(_RepeatChar("-", screenLabel:length + 6)).
			}
		}

		local headerLineBreak is "---" + headerUnderlines:join("---") + "---".

		clearScreen.
		printLn("   " + headerTabs:join("   ") + "   ", 0).
		printLn(headerLineBreak + _RepeatChar("-", terminal:width - headerLineBreak:length), 1).
	}

	function _BuildActiveLines {
		parameter viewerState.

		local screenIndex is _FindScreenIndex(viewerState, viewerState:activeScreen).
		if screenIndex < 0 return list().

		local screenDefinition is viewerState:screens[screenIndex].
		local lines is list("# " + screenDefinition:title).

		for fieldDefinition in screenDefinition:fields {
			if fieldDefinition:isType("String") {
				lines:add("-").
			}
			else if fieldDefinition:isType("Lexicon") {
				local rawValue is fieldDefinition:read().
				local fieldValue is _FormatFieldValue(rawValue, fieldDefinition:formatter).
				lines:add(
					fieldDefinition:label:padLeft(screenDefinition:fieldWidth) +
					": " + fieldValue
				).
			}
		}

		return lines.
	}

	function _RenderFrame {
		parameter viewerState.

		if viewerState:screens:length = 0 {
			if viewerState:dirty {
				clearScreen.
				printLn("No telemetry screens loaded", 0).
				set viewerState:dirty to false.
			}
			return.
		}

		local lines is _BuildActiveLines(viewerState).
		local frameWidth is 0.
		for lineText in lines {
			set frameWidth to max(frameWidth, lineText:length).
		}

		_EnsureTerminalSize(viewerState, frameWidth).

		for lineIndex in range(lines:length) {
			if lines[lineIndex] = "-" {
				set lines[lineIndex] to "  " + _RepeatChar("-", terminal:width - 4).
			}
		}

		if viewerState:dirty {
			_RenderHeader(viewerState).
			set viewerState:dirty to false.
		}

		for lineIndex in range(lines:length) {
			printLn(lines[lineIndex], lineIndex + 2).
		}
	}

	// ============================================================================
	// Private input handling
	// ============================================================================

	function _SelectScreenIndex {
		parameter viewerState, screenIndex.

		if screenIndex < 0 or screenIndex >= viewerState:screens:length return false.

		local screenName is viewerState:screens[screenIndex]:name.
		if viewerState:activeScreen <> screenName {
			set viewerState:activeScreen to screenName.
			set viewerState:dirty to true.
		}
		return true.
	}

	function _ProcessInput {
		parameter viewerState.

		until not terminal:input:hasChar {
			local inputChar is terminal:input:getChar().

			if viewerState:screens:length > 0 {
				local activeIndex is _FindScreenIndex(viewerState, viewerState:activeScreen).
				if inputChar = terminal:input:leftCursorOne {
					_SelectScreenIndex(viewerState, max(0, activeIndex - 1)).
				}
				else if inputChar = terminal:input:rightCursorOne {
					_SelectScreenIndex(viewerState, min(viewerState:screens:length - 1, activeIndex + 1)).
				}
				else {
					local numericIndex is inputChar:toScalar(-1).
					if numericIndex >= 0 and numericIndex < viewerState:screens:length {
						_SelectScreenIndex(viewerState, numericIndex).
					}
				}
			}
		}
	}

	// ============================================================================
	// Interface functions
	// ============================================================================

	function interfaceAddScreen {
		parameter viewerState, screenName, screenDefinition.

		local screenResult is _BuildScreen(viewerState, screenName, screenDefinition).
		if not screenResult:ok return screenResult.

		viewerState:screens:add(screenResult:val).
		if viewerState:activeScreen = "" {
			set viewerState:activeScreen to screenName.
		}
		_RecalculateLayout(viewerState).
		return ApiOK().
	}

	function interfaceAddFields {
		parameter viewerState, screenName, fieldDefinitions.

		local screenIndex is _FindScreenIndex(viewerState, screenName).
		if screenIndex < 0 {
			return ApiFail("Telemetry screen not found: " + screenName).
		}

		local fieldsResult is _BuildFields(fieldDefinitions).
		if not fieldsResult:ok return fieldsResult.

		local screenDefinition is viewerState:screens[screenIndex].
		for fieldDefinition in fieldsResult:val:fields {
			screenDefinition:fields:add(fieldDefinition).
		}
		set screenDefinition:fieldWidth to max(
			screenDefinition:fieldWidth,
			fieldsResult:val:fieldWidth
		).

		_RecalculateLayout(viewerState).
		return ApiOK().
	}

	function interfaceRemoveScreen {
		parameter viewerState, screenName.

		local screenIndex is _FindScreenIndex(viewerState, screenName).
		if screenIndex < 0 {
			return ApiFail("Telemetry screen not found: " + screenName).
		}

		if viewerState:activeScreen = screenName {
			if viewerState:screens:length = 1 {
				set viewerState:activeScreen to "".
			}
			else if screenIndex > 0 {
				set viewerState:activeScreen to viewerState:screens[screenIndex - 1]:name.
			}
			else {
				set viewerState:activeScreen to viewerState:screens[1]:name.
			}
		}

		viewerState:screens:remove(screenIndex).
		_RecalculateLayout(viewerState).
		return ApiOK().
	}

	function interfaceShowScreen {
		parameter viewerState, screenName.

		local screenIndex is _FindScreenIndex(viewerState, screenName).
		if screenIndex < 0 {
			return ApiFail("Telemetry screen not found: " + screenName).
		}

		_SelectScreenIndex(viewerState, screenIndex).
		return ApiOK().
	}

	function interfaceHasScreen {
		parameter viewerState, screenName.
		return _FindScreenIndex(viewerState, screenName) >= 0.
	}

	function interfaceCurrentScreen {
		parameter viewerState.
		return viewerState:activeScreen.
	}

	function interfaceRedraw {
		parameter viewerState.
		set viewerState:dirty to true.
	}

	function interfaceTick {
		parameter viewerState.

		_ProcessInput(viewerState).
		_RenderFrame(viewerState).
	}

	// ============================================================================
	// Constructor
	// ============================================================================

	function createTelemetryViewer {
		parameter minHeight is terminal:height, minWidth is terminal:width.

		local viewerState is lex(
			"screens", list(),
			"activeScreen", "",
			"minHeight", max(3, minHeight),
			"minWidth", max(3, minWidth),
			"layoutWidth", 0,
			"layoutHeight", 3,
			"contentWidth", 0,
			"dirty", true
		).

		return lex(
			"screen", interfaceAddScreen@:bind(viewerState),
			"fields", interfaceAddFields@:bind(viewerState),
			"remove", interfaceRemoveScreen@:bind(viewerState),
			"show", interfaceShowScreen@:bind(viewerState),
			"has", interfaceHasScreen@:bind(viewerState),
			"current", interfaceCurrentScreen@:bind(viewerState),
			"redraw", interfaceRedraw@:bind(viewerState),
			"tick", interfaceTick@:bind(viewerState)
		).
	}

	export(lex("create", createTelemetryViewer@)).
}