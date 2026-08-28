// ============================================================================
// KLZ2
//
// Lossy-formatting / lossless-code KerboScript compressor.
//
// Source normalization performed before compression:
//   - strips // comments outside strings
//   - normalizes CRLF and CR line endings to LF outside strings
//   - collapses repeated newlines
//   - collapses horizontal whitespace
//   - folds newlines inside (...) and [...]
//   - folds newline between closing )/] and a following statement period
//
// The resulting source is semantically equivalent KerboScript, but comments
// and original formatting are intentionally not restored by unpack().
//
// Packed representation:
//   KLZ2                        magic
//
//   ordinary character         literal
//   ~x                         escaped reserved literal
//
//   ! + D  + L                 1 digit distance, 1 digit length
//   # + D  + LL                1 digit distance, 2 digit length
//   $ + DD + L                 2 digit distance, 1 digit length
//   % + DD + LL                2 digit distance, 2 digit length
//   & + DDD + L                3 digit distance, 1 digit length
//   ; + DDD + LL               3 digit distance, 2 digit length
//
// Base-94 digits use ASCII 32..125.
// "~" (126) is therefore never used as an encoded number digit.
//
// Reference distances:
//   1 digit  = 1 .. 94
//   2 digits = 1 .. 8836
//   3 digits = 1 .. 830584
//
// Reference lengths:
//   1 digit  = 4 .. 97
//   2 digits = 4 .. 8839
//
// Overlapping references are supported.
// ============================================================================

function FN_PROGRESS{parameter s,d,n,i,l. s. d. n. i. l.}.

// ============================================================================
// PACKER
// ============================================================================

local _kpMagic is "KLZ2".

local _kpEscape is "~".
local _kpOpcodes is "!#$%&;".

local _kpBase is 94.
local _kpMinMatch is 4.

local _kpMaxD1 is 94.
local _kpMaxD2 is 8836.       // 94^2
local _kpMaxD3 is 830584.     // 94^3

local _kpMaxL1 is 97.         // 4 + 94 - 1
local _kpMaxL2 is 8839.       // 4 + 94^2 - 1

//
// Is this character reserved by the KLZ2 token stream?
//
local function _kpIsReserved {
	parameter c.

	if c = _kpEscape return true.

	local i is 0.

	until i >= _kpOpcodes:length {

		if c = _kpOpcodes[i] return true.

		set i to i + 1.
	}

	return false.
}

//
// Return the number of UTF-8 bytes required to store one literal.
//
// Reserved KLZ2 characters require an escape prefix and therefore
// occupy two bytes.
//
local function _kpLiteralCost {
	parameter c.

	if _kpIsReserved(c) return 2.

	local u is unchar(c).

	if u <= 127 return 1.
	if u <= 2047 return 2.
	if u <= 65535 return 3.

	return 4.
}

//
// Encode a non-negative integer using exactly width base-94 digits.
//
// Digit values 0..93 map to ASCII 32..125.
//
local function _kpEncode94 {
	parameter value, width.

	local result is "".
	local i is 0.

	until i >= width {

		local digit is mod(value, _kpBase).

		set result to char(32 + digit) + result.
		set value to floor(value / _kpBase).

		set i to i + 1.
	}

	return result.
}

//
// Update one leaf in the minimum-cost segment tree.
//
// indexes[] stores the corresponding source position.
//
// On equal cost the later position wins, which means the longer
// back-reference is preferred.
//
local function _kpTreeSet {
	parameter costs, indexes, base, position, value.

	local kpNode is base + position.

	set costs[kpNode] to value.
	set indexes[kpNode] to position.

	set kpNode to floor(kpNode / 2).

	until kpNode < 1 {

		local left is kpNode * 2.
		local right is left + 1.
		local useLeft is false.

		if costs[left] < costs[right] {

			set useLeft to true.

		} else if costs[left] = costs[right] {

			if indexes[left] > indexes[right] {
				set useLeft to true.
			}
		}

		if useLeft {

			set costs[kpNode] to costs[left].
			set indexes[kpNode] to indexes[left].

		} else {

			set costs[kpNode] to costs[right].
			set indexes[kpNode] to indexes[right].
		}

		set kpNode to floor(kpNode / 2).
	}
}

//
// Find the minimum encoded cost over an inclusive source-position range.
//
// Returns:
//   LIST(cost, position)
//
local function _kpTreeMin {
	parameter costs,
			  indexes,
			  base,
			  rangeLeft,
			  rangeRight.

	local bestCost is 1e30.
	local bestIndex is -1.

	local left is base + rangeLeft.
	local right is base + rangeRight.

	until left > right {

		if mod(left, 2) = 1 {

			if costs[left] < bestCost
			or (
				costs[left] = bestCost
				and indexes[left] > bestIndex
			) {
				set bestCost to costs[left].
				set bestIndex to indexes[left].
			}

			set left to left + 1.
		}

		if mod(right, 2) = 0 {

			if costs[right] < bestCost
			or (
				costs[right] = bestCost
				and indexes[right] > bestIndex
			) {
				set bestCost to costs[right].
				set bestIndex to indexes[right].
			}

			set right to right - 1.
		}

		set left to floor(left / 2).
		set right to floor(right / 2).
	}

	return list(bestCost, bestIndex).
}

//
// Consider all reference lengths in one constant-cost length range.
//
// state:
//   [0] = current best encoded cost
//   [1] = chosen source length
//   [2] = chosen reference distance
//
local function _kpTryReference {
	parameter treeCosts,
			  treeIndexes,
			  treeBase,
			  position,
			  availableLength,
			  minimumLength,
			  maximumLength,
			  referenceCost,
			  distance,
			  state.

	if availableLength < minimumLength return.

	local lastLength is min(
		availableLength,
		maximumLength
	).

	local result is _kpTreeMin(
		treeCosts,
		treeIndexes,
		treeBase,
		position + minimumLength,
		position + lastLength
	).

	if result[1] < 0 return.

	local candidateCost is referenceCost + result[0].
	local candidateLength is result[1] - position.

	if candidateCost < state[0]
	or (
		candidateCost = state[0]
		and candidateLength > state[1]
	) {
		set state[0] to candidateCost.
		set state[1] to candidateLength.
		set state[2] to distance.
	}
}

// ============================================================================
// SOURCE NORMALIZATION
// ============================================================================

//
// Determine which whitespace should be emitted immediately before
// nextCharacter.
//
// pendingWhitespace:
//   0 = none
//   1 = horizontal whitespace
//   2 = one or more line breaks
//
// Newlines inside (...) and [...] are folded to spaces.
//
// If the newline immediately follows "(" or "[" or immediately precedes
// ")" or "]", no space is needed.
//
// A newline between ")" / "]" and "." is also unnecessary:
//
//     foo(
//         bar
//     ).
//
// becomes:
//
//     foo(bar).
//
local function _kpWhitespaceSeparator {
	parameter output,
			  pendingWhitespace,
			  parenDepth,
			  bracketDepth,
			  nextCharacter.

	if pendingWhitespace = 0 return "".
	if output:length = 0 return "".

	local previous is output[output:length - 1].

	// Ordinary horizontal whitespace.
	if pendingWhitespace = 1 {
		return " ".
	}

	// Fold newlines inside explicit expression/index grouping.
	if parenDepth > 0 or bracketDepth > 0 {

		if previous = "(" or previous = "[" {
			return "".
		}

		if nextCharacter = ")"
		or nextCharacter = "]"
		or nextCharacter = "." {
			return "".
		}

		return " ".
	}

	// A common multiline instruction form:
	//
	//     foo(
	//         ...
	//     ).
	//
	// At this point the closing bracket has already reduced the
	// grouping depth to zero, so handle the final newline specially.
	if (
		previous = ")"
		or previous = "]"
	)
	and nextCharacter = "." {
		return "".
	}

	// Preserve one real source line.
	return char(10).
}

//
// Normalize KerboScript source.
//
// This is intentionally not a complete KerboScript parser.
//
// It performs only transformations that are straightforward to identify:
//
//   - comments are recognized only outside string literals
//   - horizontal whitespace is collapsed
//   - CRLF and CR become LF
//   - repeated newlines become one
//   - newlines inside (...) and [...] are folded
//
// String contents are preserved exactly.
//
// In particular, an escaped quote \" does not terminate a string.
//
local function _kpNormalizeSource {
	parameter src, dst, fnProgress is FN_PROGRESS@.

	fnProgress(src, dst, "packing (reading...)", 0, 1).
	local sourceText is open(src):readall:string.

	local output is list().
	local sourceLength is sourceText:length.

	local inString is false.

	local parenDepth is 0.
	local bracketDepth is 0.

	// 0 = none
	// 1 = horizontal whitespace
	// 2 = newline
	local pendingWhitespace is 0.

	local i is 0.

	until i >= sourceLength {
		fnProgress(src, dst, "normalizing", i, sourceLength).

		local c is sourceText[i].
		local u is unchar(c).

		// --------------------------------------------------------------------
		// Inside a string literal.
		//
		// Preserve its contents exactly.
		// --------------------------------------------------------------------

		if inString {

			output:add(c).

			// Preserve an escape and the following character together.
			//
			// Most importantly, \" must not be interpreted as the
			// end of the string.
			if u = 92
			and i + 1 < sourceLength {

				output:add(
					sourceText[i + 1]
				).

				set i to i + 2.

			} else {

				// Unescaped quote terminates the string.
				if u = 34 {
					set inString to false.
				}

				set i to i + 1.
			}

		// --------------------------------------------------------------------
		// Start of string literal.
		// --------------------------------------------------------------------

		} else if u = 34 {

			local separator is _kpWhitespaceSeparator(
				output,
				pendingWhitespace,
				parenDepth,
				bracketDepth,
				c
			).

			if separator:length > 0 {
				output:add(separator).
			}

			set pendingWhitespace to 0.

			output:add(c).

			set inString to true.
			set i to i + 1.

		// --------------------------------------------------------------------
		// // comment.
		//
		// Do not consume its terminating newline here.  Leaving i pointing
		// at CR/LF lets the normal newline logic handle CR, LF and CRLF in
		// exactly the same way as ordinary source lines.
		// --------------------------------------------------------------------

		} else if c = "/"
		and i + 1 < sourceLength
		and sourceText[i + 1] = "/" {

			set i to i + 2.

			until i >= sourceLength
			or unchar(sourceText[i]) = 10
			or unchar(sourceText[i]) = 13 {

				set i to i + 1.
			}

		// --------------------------------------------------------------------
		// Horizontal whitespace.
		//
		// Do not downgrade a pending newline back to ordinary whitespace.
		// This also removes indentation following a retained newline.
		// --------------------------------------------------------------------

		} else if u = 32
		or u = 9 {

			if pendingWhitespace < 2 {
				set pendingWhitespace to 1.
			}

			set i to i + 1.

		// --------------------------------------------------------------------
		// Newline.
		//
		// LF       -> LF
		// CR       -> LF
		// CR LF    -> LF
		//
		// Multiple consecutive line endings remain a single pending newline.
		// --------------------------------------------------------------------

		} else if u = 10
		or u = 13 {

			set pendingWhitespace to 2.

			// Consume CRLF as one logical newline.
			if u = 13
			and i + 1 < sourceLength
			and unchar(sourceText[i + 1]) = 10 {

				set i to i + 2.

			} else {

				set i to i + 1.
			}

		// --------------------------------------------------------------------
		// Ordinary source character.
		// --------------------------------------------------------------------

		} else {

			local separator is _kpWhitespaceSeparator(
				output,
				pendingWhitespace,
				parenDepth,
				bracketDepth,
				c
			).

			if separator:length > 0 {
				output:add(separator).
			}

			set pendingWhitespace to 0.

			output:add(c).

			// Track only the two forms of grouping for which we deliberately
			// fold internal newlines.
			if c = "(" {

				set parenDepth to parenDepth + 1.

			} else if c = ")" {

				if parenDepth > 0 {
					set parenDepth to parenDepth - 1.
				}

			} else if c = "[" {

				set bracketDepth to bracketDepth + 1.

			} else if c = "]" {

				if bracketDepth > 0 {
					set bracketDepth to bracketDepth - 1.
				}
			}

			set i to i + 1.
		}
	}

	// Preserve one final newline if the original normalized source ended
	// with one or more line endings.
	if pendingWhitespace = 2
	and output:length > 0 {

		output:add(
			char(10)
		).
	}

	return output:join("").
}

// ============================================================================
// PACK
// ============================================================================

//
// Pack a UTF-8 KerboScript text file.
//
// src and dst may be absolute kOS paths.
//
// Returns:
//   true  = packed file successfully written
//   false = source missing or destination write failed
//
function pack {
	parameter src, dst, fnProgress is FN_PROGRESS@.

	if not exists(src) return false.

	local sourceText is _kpNormalizeSource(src, dst, fnProgress).

	local sourceLength is sourceText:length.

	// ========================================================================
	// PASS 1
	//
	// Find the longest previous match at every source position,
	// independently for 1-, 2-, and 3-digit distance references.
	//
	// Unlike KLZ1, this search is not candidate-limited.
	// ========================================================================

	local matchLen1 is list().
	local matchDist1 is list().

	local matchLen2 is list().
	local matchDist2 is list().

	local matchLen3 is list().
	local matchDist3 is list().

	// Maps an exact 4-character prefix to previous source positions.
	local positionMap is lexicon().

	set positionMap:casesensitive to true.

	local i is 0.

	until i >= sourceLength {
		fnProgress(src, dst, "packing (PASS 1)", i, sourceLength).

		local bestLen1 is 0.
		local bestDist1 is 0.

		local bestLen2 is 0.
		local bestDist2 is 0.

		local bestLen3 is 0.
		local bestDist3 is 0.

		if i + _kpMinMatch <= sourceLength {

			local key is sourceText:substring(
				i,
				_kpMinMatch
			).

			local possibleMax is min(
				_kpMaxL2,
				sourceLength - i
			).

			if positionMap:haskey(key) {

				local candidates is positionMap[key].

				local candidateIndex is
					candidates:length - 1.

				until candidateIndex < 0 {

					local previous is
						candidates[candidateIndex].

					local distance is i - previous.

					// Older candidates cannot be represented.
					if distance > _kpMaxD3 {

						set candidateIndex to -1.

					} else {

						local distanceClass is 0.
						local currentBest is 0.

						if distance <= _kpMaxD1 {

							set distanceClass to 1.
							set currentBest to bestLen1.

						} else if distance <= _kpMaxD2 {

							set distanceClass to 2.
							set currentBest to bestLen2.

						} else {

							set distanceClass to 3.
							set currentBest to bestLen3.
						}

						local canBeat is
							currentBest < possibleMax.

						// If we already have a match longer than the prefix,
						// test the first character that a new candidate would
						// have to match in order to improve it.
						if canBeat
						and currentBest >= _kpMinMatch {

							if unchar(
								sourceText[
									previous + currentBest
								]
							)
							<> unchar(
								sourceText[
									i + currentBest
								]
							) {
								set canBeat to false.
							}
						}

						if canBeat {

							// The first _kpMinMatch characters are already
							// known to match because the case-sensitive
							// prefix key matched.
							local matchLength is _kpMinMatch.

							until matchLength >= possibleMax {

								if unchar(sourceText[previous + matchLength])
								<> unchar(sourceText[i + matchLength]) {
									break.
								}

								set matchLength to matchLength + 1.
							}

							if matchLength > currentBest {

								if distanceClass = 1 {

									set bestLen1 to
										matchLength.

									set bestDist1 to
										distance.

								} else if distanceClass = 2 {

									set bestLen2 to
										matchLength.

									set bestDist2 to
										distance.

								} else {

									set bestLen3 to
										matchLength.

									set bestDist3 to
										distance.
								}
							}
						}

						// A full-length class-1 match is optimal.
						if bestLen1 = possibleMax {

							set candidateIndex to -1.

						// Once all class-1 candidates are behind us, a
						// full-length class-2 match also makes class 3
						// irrelevant because class 3 costs more bytes.
						} else if distance > _kpMaxD1
						and bestLen2 = possibleMax {

							set candidateIndex to -1.

						} else {

							set candidateIndex to
								candidateIndex - 1.
						}
					}
				}
			}

			// Make this source position available to subsequent matches.
			if positionMap:haskey(key) {

				local bucket is positionMap[key].

				bucket:add(i).

			} else {

				set positionMap[key] to list(i).
			}
		}

		matchLen1:add(bestLen1).
		matchDist1:add(bestDist1).

		matchLen2:add(bestLen2).
		matchDist2:add(bestDist2).

		matchLen3:add(bestLen3).
		matchDist3:add(bestDist3).

		set i to i + 1.
	}

	// ========================================================================
	// PASS 2
	//
	// Dynamic programming:
	//
	// Find the minimum-size token sequence using the matches discovered
	// above.
	// ========================================================================

	local cost is list().
	local choiceLength is list().
	local choiceDistance is list().

	set i to 0.

	until i > sourceLength {
		fnProgress(src, dst, "packing (Pass 2: initializing)", i, sourceLength).

		cost:add(1e30).
		choiceLength:add(1).
		choiceDistance:add(0).

		set i to i + 1.
	}

	// Segment tree containing cost[position] for already-solved positions
	// to the right of the current position.
	local treeBase is 1.

	until treeBase >= sourceLength + 1 {

		set treeBase to treeBase * 2.
	}

	local treeCosts is list().
	local treeIndexes is list().

	set i to 0.

	until i >= treeBase * 2 {
		fnProgress(src, dst, "packing (Pass 2: preparing tree)", i, treeBase * 2).

		treeCosts:add(1e30).
		treeIndexes:add(-1).

		set i to i + 1.
	}

	set cost[sourceLength] to 0.

	_kpTreeSet(
		treeCosts,
		treeIndexes,
		treeBase,
		sourceLength,
		0
	).

	set i to sourceLength - 1.

	until i < 0 {

		// Default choice: one literal character.
		local state is list(
			_kpLiteralCost(
				sourceText[i]
			)
			+ cost[i + 1],

			1,
			0
		).

		// KLZ2 reference costs:
		//
		//                  length width
		//                   1     2
		//
		// distance 1        3     4
		// distance 2        4     5
		// distance 3        5     6
		//
		// Each reference contains:
		//
		//   opcode + distance digits + length digits

		// --------------------------------------------------------------------
		// Distance width 1.
		// --------------------------------------------------------------------

		if matchLen1[i] >= _kpMinMatch {

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen1[i],
				_kpMinMatch,
				_kpMaxL1,
				3,
				matchDist1[i],
				state
			).

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen1[i],
				_kpMaxL1 + 1,
				_kpMaxL2,
				4,
				matchDist1[i],
				state
			).
		}

		// --------------------------------------------------------------------
		// Distance width 2.
		// --------------------------------------------------------------------

		if matchLen2[i] >= _kpMinMatch {

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen2[i],
				_kpMinMatch,
				_kpMaxL1,
				4,
				matchDist2[i],
				state
			).

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen2[i],
				_kpMaxL1 + 1,
				_kpMaxL2,
				5,
				matchDist2[i],
				state
			).
		}

		// --------------------------------------------------------------------
		// Distance width 3.
		// --------------------------------------------------------------------

		if matchLen3[i] >= _kpMinMatch {

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen3[i],
				_kpMinMatch,
				_kpMaxL1,
				5,
				matchDist3[i],
				state
			).

			_kpTryReference(
				treeCosts,
				treeIndexes,
				treeBase,
				i,
				matchLen3[i],
				_kpMaxL1 + 1,
				_kpMaxL2,
				6,
				matchDist3[i],
				state
			).
		}

		set cost[i] to state[0].
		set choiceLength[i] to state[1].
		set choiceDistance[i] to state[2].

		_kpTreeSet(
			treeCosts,
			treeIndexes,
			treeBase,
			i,
			cost[i]
		).

		set i to i - 1.

		fnProgress(src, dst, "packing (Pass 2: optimizing)", sourceLength - i - 1, sourceLength).
	}

	// ========================================================================
	// PASS 3
	//
	// Emit the selected representation.
	// ========================================================================

	local packedParts is list(
		_kpMagic
	).

	set i to 0.

	until i >= sourceLength {
		fnProgress(src, dst, "packing (PASS 3)", i, sourceLength).

		local length is choiceLength[i].

		// --------------------------------------------------------------------
		// Literal.
		// --------------------------------------------------------------------

		if length = 1 {

			local c is sourceText[i].

			if _kpIsReserved(c) {

				packedParts:add(
					_kpEscape + c
				).

			} else {

				packedParts:add(c).
			}

			set i to i + 1.

		// --------------------------------------------------------------------
		// Back-reference.
		// --------------------------------------------------------------------

		} else {

			local distance is
				choiceDistance[i].

			local distanceWidth is 3.

			if distance <= _kpMaxD1 {

				set distanceWidth to 1.

			} else if distance <= _kpMaxD2 {

				set distanceWidth to 2.
			}

			local lengthWidth is 2.

			if length <= _kpMaxL1 {

				set lengthWidth to 1.
			}

			// Modes:
			//
			//   0  !  distance 1, length 1
			//   1  #  distance 1, length 2
			//   2  $  distance 2, length 1
			//   3  %  distance 2, length 2
			//   4  &  distance 3, length 1
			//   5  ;  distance 3, length 2

			local mode is
				(distanceWidth - 1) * 2
				+ (lengthWidth - 1).

			local token is
				_kpOpcodes[mode]
				+ _kpEncode94(
					distance - 1,
					distanceWidth
				)
				+ _kpEncode94(
					length - _kpMinMatch,
					lengthWidth
				).

			packedParts:add(token).

			set i to i + length.
		}
	}

	fnProgress(src, dst, "packing (assembling...)", 0, 1).
	local packedText is packedParts:join("").

	fnProgress(src, dst, "packing (writing...)", 0, 1).
	// Source has already been completely loaded into memory, so src = dst
	// is safe if desired.
	if exists(dst) {

		deletepath(dst).
	}

	local destination is create(dst).

	if not destination:write(packedText) {

		if exists(dst) {

			deletepath(dst).
		}

		fnProgress(src, dst, "packing (failed)", 1, 1).
		return false.
	}

	fnProgress(src, dst, "packing (completed)", 1, 1).
	return true.
}

// ============================================================================
// UNPACKER
//
// This section is deliberately independent from the packer so it can be
// extracted into a small mission-side library.
// ============================================================================

local _kuMagic is "KLZ2".

local _kuEscape is "~".

local _kuBase is 94.
local _kuMinMatch is 4.

//
// Convert a KLZ2 opcode into its reference mode.
//
// Returns -1 when c is an ordinary literal.
//
local function _kuMode {
	parameter c.

	if c = "!" return 0.
	if c = "#" return 1.
	if c = "$" return 2.
	if c = "%" return 3.
	if c = "&" return 4.
	if c = ";" return 5.

	return -1.
}

//
// Is c permitted immediately after the KLZ2 escape character?
//
local function _kuIsEscapedLiteral {
	parameter c.

	if c = _kuEscape return true.
	if _kuMode(c) >= 0 return true.

	return false.
}

//
// Decode exactly width base-94 digits.
//
local function _kuDecode94 {
	parameter text, start, width.

	local value is 0.
	local i is 0.

	until i >= width {

		local digit is
			unchar(text[start + i]) - 32.

		if digit < 0
		or digit >= _kuBase {

			return -1.
		}

		set value to
			value * _kuBase
			+ digit.

		set i to i + 1.
	}

	return value.
}

//
// Unpack a KLZ2 file.
//
// Returns:
//   true  = unpacked file successfully written
//   false = source missing, malformed KLZ2 data, or write failure
//
// dst is left untouched if the packed data itself is malformed.
//
function unpack {
	parameter src, dst, fnProgress is FN_PROGRESS@.

	if not exists(src) return false.

	fnProgress(src, dst, "unpacking (reading...)", 0, 1).
	local packed is open(src):readall:string.

	if packed:length < 4 return false.

	// ------------------------------------------------------------------------
	// Verify magic case-sensitively.
	// ------------------------------------------------------------------------

	local validMagic is true.
	local i is 0.

	until i >= 4 {

		if unchar(packed[i])
		<> unchar(_kuMagic[i]) {

			set validMagic to false.
			set i to 4.

		} else {

			set i to i + 1.
		}
	}

	if not validMagic return false.

	// ------------------------------------------------------------------------
	// Decode.
	// ------------------------------------------------------------------------

	local output is list().

	set i to 4.

	until i >= packed:length {
		fnProgress(src, dst, "unpacking", i, packed:length).

		local c is packed[i].

		// --------------------------------------------------------------------
		// Escaped reserved literal.
		// --------------------------------------------------------------------

		if c = _kuEscape {

			if i + 1 >= packed:length {

				return false.
			}

			local literal is
				packed[i + 1].

			if not _kuIsEscapedLiteral(literal) {

				return false.
			}

			output:add(literal).

			set i to i + 2.

		// --------------------------------------------------------------------
		// Reference opcode or ordinary literal.
		// --------------------------------------------------------------------

		} else {

			local mode is _kuMode(c).

			// ----------------------------------------------------------------
			// Ordinary literal.
			// ----------------------------------------------------------------

			if mode < 0 {

				output:add(c).

				set i to i + 1.

			// ----------------------------------------------------------------
			// Back-reference.
			// ----------------------------------------------------------------

			} else {

				local distanceWidth is
					floor(mode / 2) + 1.

				local lengthWidth is
					mod(mode, 2) + 1.

				// opcode
				// + distance digits
				// + length digits
				local tokenEnd is
					i
					+ 1
					+ distanceWidth
					+ lengthWidth.

				if tokenEnd > packed:length {

					return false.
				}

				local distanceCode is
					_kuDecode94(
						packed,
						i + 1,
						distanceWidth
					).

				local lengthCode is
					_kuDecode94(
						packed,
						i + 1 + distanceWidth,
						lengthWidth
					).

				if distanceCode < 0
				or lengthCode < 0 {

					return false.
				}

				local distance is
					distanceCode + 1.

				local length is
					lengthCode + _kuMinMatch.

				// A reference may only start inside data already decoded.
				if distance > output:length {

					return false.
				}

				// output:length changes during the copy.
				//
				// This deliberately permits overlapping references.
				local copied is 0.

				until copied >= length {

					output:add(
						output[
							output:length - distance
						]
					).

					set copied to copied + 1.
				}

				set i to tokenEnd.
			}
		}
	}

	fnProgress(src, dst, "unpacking (assembling...)", 0, 1).
	local unpacked is output:join("").


	fnProgress(src, dst, "unpacking (writing...)", 0, 1).
	// ------------------------------------------------------------------------
	// Only replace dst after the complete packed stream has been validated.
	// ------------------------------------------------------------------------
	if exists(dst) {

		deletepath(dst).
	}

	local destination is
		create(dst).

	if not destination:write(unpacked) {

		if exists(dst) {

			deletepath(dst).
		}

		fnProgress(src, dst, "unpacking (failed)", 1, 1).
		return false.
	}

	fnProgress(src, dst, "unpacking (completed)", 1, 1).
	return true.
}

// ============================================================================
// TEST
// ============================================================================

clearScreen.
local oldIpu is config:ipu.
set config:ipu to 2000.
function showProgress {
	parameter src, dst, stepName, index, length, firstLine is 0.
	print (stepName + ": " + (round(index / length * 100, 1) + "%")):padright(terminal:width) at (0, firstLine).
	print ("  src: " + src):padright(terminal:width) at (0, firstLine + 1).
	print ("  dst: " + dst):padright(terminal:width) at (0, firstLine + 2).
}
pack("0:/klz2.ks", "0:/klz2.packed.ksz", {parameter src, dst, stepName, index, length. showProgress(src, dst, stepName, index, length, 0).}).
unpack("0:/klz2.packed.ksz", "0:/klz2.unpacked.ks", {parameter src, dst, stepName, index, length. showProgress(src, dst, stepName, index, length, 3).}).
set config:ipu to oldIpu.