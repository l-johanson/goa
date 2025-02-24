#
# \brief  Generate ABI symbol list for a shared library
# \author Norman Feske
# \author Pirmin Duss
# \date   2016-12-07
#
# The tool takes the shared library as argument and writes the output to
# standard output. Each line of the resulting output contains the symbol name,
# type, and size
#

proc abi_symbols_from_library { library_file_path symbols_file_fd } {
	global tool_dir

	# normalize sort order across platforms
	set env(LC_ALL) C

	# obtain symbol information via 'nm'
	set symbols [exec nm --format posix --dynamic $library_file_path | sort]

	# obtain demangled input via c++filt
	set demangled [exec c++filt << $symbols]

	set demangled_lines [split $demangled "\n"]

	# obtail list of blacklisted symbols
	set fd [open [file join $tool_dir abi internal_abi.list]]
	set symbol_blacklist [split [read $fd] "\n"]
	close $fd

	# add notice that the symbols file hasn't undergone any manual inspection
	puts $symbols_file_fd "# Please review the symbols and remove this line."

	set i 0
	foreach line [split $symbols "\n"] {

		set size_hex 0
		set type "U"

		# match undefined symbol
		if {![regexp {^(\w+) U\s*$} $line dummy name]} {

			# match defined symbol, which does not always feature a value or size
			if {![regexp {^([\w.]+) (\w) *\w* ?(\w*)$} $line dummy name type size_hex]} {
				puts stderr "Error: unexpected format of line: $line"
				exit -1
			}
		}

		# decimal symbol size
		set size_dec [expr 0x0$size_hex]

		set demangled_name $name
		regexp {^(.+) \w \w+( \w+)?$} [lindex $demangled_lines $i] dummy demangled_name

		set keep 1

		#
		# Ignore undefined symbols
		#
		if {$type == "U"} { set keep 0 }

		#
		# Check if the unmangled line contains a template-argument delimiter ('<')
		# prior the first opening parenthesis. This way, template methods match but
		# signatures of non-template functions/methods that take templated
		# arguments won't. We can discard symbols for the former but not the
		# latter.
		#
		if {[regexp {^[^(]+<} $demangled_name dummy]} { set keep 0 }

		#
		# Drop weak vtable and typeinfo symbols
		#
		# Those symbols are solely used to merge vtables between the executable and
		# shared library. When linking object files that use the same types, the
		# merging saves a lot space. However, the benefit at the coarse granularity
		# of shared libraries is rather small compared to the huge inflation of the
		# ABI size caused by such symbols.
		#
		if {($type == "V") && ([regexp {^(typeinfo |vtable )} $demangled_name dummy])} {
			set keep 0 }

		#
		# Drop weak C++ symbols
		#
		# In contrast to weak C symbols, which are rarely and always deliberately
		# created, weak C++ symbols are implicitly created by the compiler for
		# inline functions.
		#
		if {[regexp {W|V} $type] && ($name != $demangled_name)} {
			set keep 0 }

		#
		# Drop weak local symbols
		#
		if {[regexp {w|v} $type]} {
			set keep 0 }

		#
		# Drop blacklisted symbols
		#
		foreach blacklisted_symbol $symbol_blacklist {
			if {$name == $blacklisted_symbol} { set keep 0 } }

		# write result
		if {$keep} {

			#
			# Annotate the size for global data symbols where the size is needed to
			# create copy relations (ARM EABI) in the binary that is linked against
			# the shared library. For each global read-only data symbol found in
			# the shared object, the linker reserves space (according to the
			# symbol's size) in the binary's BSS segment. At runtime, the dynamic
			# linker copies the data from the shared library's symbol into the
			# binary's BSS.
			#
			if {($type == "D") || ($type == "B") || ($type == "R")} {
				puts $symbols_file_fd "$name $type $size_dec"
			} else {
				puts $symbols_file_fd "$name $type"
			}
		}
		incr i
	}
}
