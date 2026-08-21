function printLn {
	parameter message, line is 0, column is 0.
	print message:tostring:padright(terminal:width) AT (column, line).
}