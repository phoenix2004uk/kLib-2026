{
	local constantE is constant:e.
	export(lex(
		"cosh", {
			parameter x.
			return (constantE^x + constantE^(-x)) / 2.
		},
		"acosh", {
			parameter x.
			return ln(x + sqrt(x^2 - 1)).
		},
		"sinh", {
			parameter x.
			return (constantE^x - constantE^(-x)) / 2.
		},
		"asinh", {
			parameter x.
			return ln(x + sqrt(x^2 + 1)).
		}
	)).
}