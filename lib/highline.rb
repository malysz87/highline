#!/usr/local/bin/ruby -w

# highline.rb
#
#  Created by James Edward Gray II on 2005-04-26.
#  Copyright 2005 Gray Productions. All rights reserved.
#
# See HighLine for documentation.

require "highline/question"
require "highline/menu"
require "erb"
require "optparse"

#
# A HighLine object is a "high-level line oriented" shell over an input and an 
# output stream.  HighLine simplifies common console interaction, effectively
# replacing puts() and gets().  User code can simply specify the question to ask
# and any details about user interaction, then leave the rest of the work to
# HighLine.  When HighLine.ask() returns, you'll have to answer you requested,
# even if HighLine had to ask many times, validate results, perform range
# checking, convert types, etc.
#
class HighLine
	# An internal HighLine error.  User code does not need to trap this.
	class QuestionError < StandardError
		# do nothing, just creating a unique error type
	end

	#
	# Embed in a String to clear all previous ANSI sequences.  This *MUST* be 
	# done before the program exits!
	# 
	CLEAR      = "\e[0m"
	# An alias for CLEAR.
	RESET      = CLEAR
	# The start of an ANSI bold sequence.
	BOLD       = "\e[1m"
	# The start of an ANSI dark sequence.  (Terminal support uncommon.)
	DARK       = "\e[2m"
	# The start of an ANSI underline sequence.
	UNDERLINE  = "\e[4m"
	# An alias for UNDERLINE.
	UNDERSCORE = UNDERLINE
	# The start of an ANSI blink sequence.  (Terminal support uncommon.)
	BLINK      = "\e[5m"
	# The start of an ANSI reverse sequence.
	REVERSE    = "\e[7m"
	# The start of an ANSI concealed sequence.  (Terminal support uncommon.)
	CONCEALED  = "\e[8m"

	# Set the terminal's foreground ANSI color to black.
	BLACK      = "\e[30m"
	# Set the terminal's foreground ANSI color to red.
	RED        = "\e[31m"
	# Set the terminal's foreground ANSI color to green.
	GREEN      = "\e[32m"
	# Set the terminal's foreground ANSI color to yellow.
	YELLOW     = "\e[33m"
	# Set the terminal's foreground ANSI color to blue.
	BLUE       = "\e[34m"
	# Set the terminal's foreground ANSI color to magenta.
	MAGENTA    = "\e[35m"
	# Set the terminal's foreground ANSI color to cyan.
	CYAN       = "\e[36m"
	# Set the terminal's foreground ANSI color to white.
	WHITE      = "\e[37m"

	# Set the terminal's background ANSI color to black.
	ON_BLACK   = "\e[40m"
	# Set the terminal's background ANSI color to red.
	ON_RED     = "\e[41m"
	# Set the terminal's background ANSI color to green.
	ON_GREEN   = "\e[42m"
	# Set the terminal's background ANSI color to yellow.
	ON_YELLOW  = "\e[43m"
	# Set the terminal's background ANSI color to blue.
	ON_BLUE    = "\e[44m"
	# Set the terminal's background ANSI color to magenta.
	ON_MAGENTA = "\e[45m"
	# Set the terminal's background ANSI color to cyan.
	ON_CYAN    = "\e[46m"
	# Set the terminal's background ANSI color to white.
	ON_WHITE   = "\e[47m"

	#
	# Create an instance of HighLine, connected to the streams _input_
	# and _output_.
	#
	def initialize( input = $stdin, output = $stdout,
		            wrap_at = nil, page_at = nil )
		@input   = input
		@output  = output
		@wrap_at = wrap_at
		@page_at = page_at
	end
	
	#
	# Set to an integer value to cause HighLine to wrap output lines at the
	# indicated character limit.  When +nil+, the default, no wrapping occurs.
	#
	attr_accessor :wrap_at
	#
	# Set to an integer value to cause HighLine to page output lines over the
	# indicated line limit.  When +nil+, the default, no paging occurs.
	#
	attr_accessor :page_at
	
	#
	# A shortcut to HighLine.ask() a question that only accepts "yes" or "no"
	# answers ("y" and "n" are allowed) and returns +true+ or +false+
	# (+true+ for "yes").  If provided a +true+ value, _character_ will cause
	# HighLine to fetch a single character response.
	#
	def agree( yes_or_no_question, character = nil )
		ask(yes_or_no_question, lambda { |yn| yn.downcase[0] == ?y}) do |q|
			q.validate                 = /\Ay(?:es)?|no?\Z/i
			q.responses[:not_valid]    = 'Please enter "yes" or "no".'
			q.responses[:ask_on_error] = :question
			q.character                = character
		end
	end
	
	#
	# This method is the primary interface for user input.  Just provide a
	# _question_ to ask the user, the _answer_type_ you want returned, and
	# optionally a code block setting up details of how you want the question
	# handled.  See HighLine.say() for details on the format of _question_, and
	# HighLine::Question for more information about _answer_type_ and what's
	# valid in the code block.
	# 
	# If <tt>@question</tt> is set before ask() is called, parameters are
	# ignored and that object (must be a HighLine::Question) is used to drive
	# the process instead.
	#
	def ask(question, answer_type = String, &details) # :yields: question
		@question ||= Question.new(question, answer_type, &details)
		
		say(@question)
		begin
			@answer = @question.answer_or_default(get_response)
			unless @question.valid_answer?(@answer)
				explain_error(:not_valid)
				raise QuestionError
			end
			
			@answer = @question.convert(@answer)
			
			if @question.in_range?(@answer)
				if @question.confirm
					# need to add a layer of scope to ask a question inside a
					# question, without destroying instance data
					context_change = self.class.new( @input, @output,
					                                 @wrap_at, @page_at )
					if @question.confirm == true
						confirm_question = "Are you sure?  "
					else
						# evaluate ERb under initial scope, so it will have
						# access to @question and @answer
						template  = ERB.new(@question.confirm, nil, "%")
						confirm_question = template.result(binding)
					end
					unless context_change.agree(confirm_question)
						explain_error(nil)
						raise QuestionError
					end
				end
				
				@answer
			else
				explain_error(:not_in_range)
				raise QuestionError
			end
		rescue QuestionError
			retry
		rescue ArgumentError
			explain_error(:invalid_type)
			retry
		rescue Question::NoAutoCompleteMatch
			explain_error(:no_completion)
			retry
		rescue NameError
			raise if $!.is_a?(NoMethodError)
			explain_error(:ambiguous_completion)
			retry
		ensure
			@question = nil    # Reset Question object.
		end
	end

	#
	# This method is HighLine's menu handler.  For simple usage, you can just
	# pass all the menu items you wish to display.  At that point, choose() will
	# build and display a menu, walk the user through selection, and return
	# their choice amoung the provided items.  You might use this in a case
	# statement for quick and dirty menus.
	# 
	# However, choose() is capable of much more.  If provided, a block will be
	# passed a HighLine::Menu object to configure.  Using this method, you can
	# customize all the details of menu handling from index display, to building
	# a complete shell-like menuing system.  See HighLine::Menu for all the
	# methods it responds to.
	# 
	def choose( *items, &details )
		@menu = @question = Menu.new(&details)
		@menu.choices(*items) unless items.empty?
		
		# Set _answer_type_ so we can double as the Question for ask().
		@menu.answer_type = if @menu.shell
			lambda do |command|    # shell-style selection
				first_word = command.split.first

				options = @menu.options
				options.extend(OptionParser::Completion)
				answer = options.complete(first_word)

				if answer.nil?
					raise Question::NoAutoCompleteMatch
				end

				[answer.last, command.sub(/^\s*#{first_word}\s*/, "")]
			end
		else
			@menu.options          # normal menu selection, by index or name
		end
		
		# Provide hooks for ERb layouts.
		@header   = @menu.header
		@prompt   = @menu.prompt
		
		if @menu.shell
			selected = ask("Ignored", @menu.answer_type)
			@menu.select(*selected)
		else
			selected = ask("Ignored", @menu.answer_type)
			@menu.select(selected)
		end
	end

	#
	# This method provides easy access to ANSI color sequences, without the user
	# needing to remember to CLEAR at the end of each sequence.  Just pass the
	# _string_ to color, followed by a list of _colors_ you would like it to be
	# affected by.  The _colors_ can be HighLine class constants, or symbols 
	# (:blue for BLUE, for example).  A CLEAR will automatically be embedded to
	# the end of the returned String.
	#
	def color( string, *colors )
		colors.map! do |c|
			if c.is_a?(Symbol)
				self.class.const_get(c.to_s.upcase)
			else
				c
			end
		end
		"#{colors.join}#{string}#{CLEAR}"
	end
	
	# 
	# This method is a utility for quickly and easily laying out lists.  It can
	# be accessed within ERb replacments of any text that will be sent to the
	# user.
	#
	# The only required parameter is _items_, which should be the Array of items
	# to list.  A specified _mode_ controls how that list is formed and _option_
	# has different effects, depending on the _mode_.  Recognized modes are:
	#
	# <tt>:columns_across</tt>::  _items_ will be placed in columns, flowing
	#                             from left to right.  If given, _option_ is the
	#                             number of columns to be used.  When absent, 
	#                             columns will be determined based on _wrap_at_
	#                             or a defauly of 80 characters.
	# <tt>:columns_down</tt>::    Indentical to <tt>:columns_across</tt>, save
	#                             flow goes down.
	# <tt>:inline</tt>::          All _items_ are placed on a single line.  The
	#                             last two _items_ are separated by _option_ or
	#                             a default of " or ".  All other _items_ are
	#                             separated by ", ".
	# <tt>:rows</tt>::            The default mode.  Each of the _items_ is
	#                             placed on it's own line.  The _option_
	#                             parameter is ignored in this mode.
	# 
	def list( items, mode = :rows, option = nil )
		items = items.to_ary
		
		case mode
		when :inline
			option = " or " if option.nil?
			
			case items.size
			when 0
				""
			when 1
				items.first
			when 2
				"#{items.first}#{option}#{items.last}"
			else
				items[0..-2].join(", ") + "#{option}#{items.last}"
			end
		when :columns_across, :columns_down
			if option.nil?
				limit = @wrap_at || 80
				max_length = items.max { |a, b| a.length <=> b.length }.length
				option = (limit + 2) / (max_length + 2)
			end

			max_length = items.max { |a, b| a.length <=> b.length }.length
			items = items.map { |item| "%-#{max_length}s" % item }
			row_count = (items.size / option.to_f).ceil
			
			if mode == :columns_across
				rows = Array.new(row_count) { Array.new }
				items.each_with_index do |item, index|
					rows[index / option] << item
				end

				rows.map { |row| row.join("  ") + "\n" }.join
			else
				columns = Array.new(option) { Array.new }
				items.each_with_index do |item, index|
					columns[index / row_count] << item
				end
			
				list = ""
				columns.first.size.times do |index|
					list << columns.map { |column| column[index] }.
					                compact.join("  ") + "\n"
				end
				list
			end
		else
			items.map { |i| "#{i}\n" }.join
		end
	end
	
	#
	# The basic output method for HighLine objects.  If the provided _statement_
	# ends with a space or tab character, a newline will not be appended (output
	# will be flush()ed).  All other cases are passed straight to Kernel.puts().
	#
	# The _statement_ parameter is processed as an ERb template, supporting
	# embedded Ruby code.  The template is evaluated with a binding inside 
	# the HighLine instance, providing easy access to the ANSI color constants
	# and the HighLine.color() method.
	#
	def say( statement )
		statement = statement.to_str
		return unless statement.length > 0
		
		template  = ERB.new(statement, nil, "%")
		statement = template.result(binding)
		
		statement = wrap(statement) unless @wrap_at.nil?
		statement = page_print(statement) unless @page_at.nil?
		
		if statement[-1, 1] == " " or statement[-1, 1] == "\t"
			@output.print(statement)
			@output.flush	
		else
			@output.puts(statement)
		end
	end
	
	private
	
	#
	# A helper method for sending the output stream and error and repeat
	# of the question.
	#
	def explain_error( error )
		say(@question.responses[error]) unless error.nil?
		if @question.responses[:ask_on_error] == :question
			say(@question)
		elsif @question.responses[:ask_on_error]
			say(@question.responses[:ask_on_error])
		end
	end
	
	#
	# This section builds a character reading function to suit the proper
	# platform we're running on.  Be warned:  Here be dragons!
	#
	begin
        require "Win32API"       # See if we're on Windows.

		CHARACTER_MODE = "Win32API"    # For Debugging purposes only.

		#
		# Windows savvy getc().
		# 
		# *WARNING*:  This method ignores <tt>@input</tt> and reads one
		# character from +STDIN+!
		# 
		def get_character
			Win32API.new("crtdll", "_getch", [ ], "L").Call
        end
    rescue LoadError             # If we're not on Windows try...
		begin
			require "termios"    # Unix, first choice.
		
			CHARACTER_MODE = "termios"    # For Debugging purposes only.

	    	#
	    	# Unix savvy getc().  (First choice.)
	    	# 
	    	# *WARNING*:  This method requires the "termios" library!
	    	# 
	        def get_character
	    		old_settings = Termios.getattr(@input)
	
	    		new_settings = old_settings.dup
				new_settings.c_lflag &= ~(Termios::ECHO | Termios::ICANON)
	    
				begin
					Termios.setattr(@input, Termios::TCSANOW, new_settings)
					@input.getc
				ensure
					Termios.setattr(@input, Termios::TCSANOW, old_settings)
				end
	        end
		rescue LoadError         # If our first choice fails, default.
			CHARACTER_MODE = "stty"    # For Debugging purposes only.

	        #
	        # Unix savvy getc().  (Second choice.)
	        # 
	        # *WARNING*:  This method requires the external "stty" program!
	        # 
	        def get_character
	            state = `stty -g`
				
				begin
		        	system "stty raw -echo cbreak"
		            @input.getc
	    	    ensure
	        	    system "stty #{state}"
				end
			end
		end
    end

    #
	# Read a line of input from the input stream and process whitespace as
	# requested by the Question object.
	#
	def get_line(  )
		@question.change_case(@question.remove_whitespace(@input.gets))
	end
	
	#
	# Return a line or character of input, as requested for this question.
	# Character input will be returned as a single character String,
	# not an Integer.
	#
	def get_response(  )
		if @question.character.nil?
			if @question.echo == true
				get_line
			else
				line = ""
				while character = get_character
					line << character.chr
					# looking for carriage return (decimal 13) or
					# newline (decimal 10) in raw input
					break if character == 13 or character == 10
					@output.print(@question.echo) if @question.echo != false
				end
				say("\n")
				@question.change_case(@question.remove_whitespace(line))
			end
		elsif @question.character == :getc
			@question.change_case(@input.getc.chr)
		else
			response = get_character.chr
			echo = if @question.echo == true
				response
			elsif @question.echo != false
				@question.echo
			else
				""
			end
			say("#{echo}\n")
			@question.change_case(response)
		end
	end
	
	# 
	# Page print a series of at most _page_at_ lines for _output_.  After each
	# page is printed, HighLine will pause until the user presses enter/return
	# then display the next page of data.
	#
	# Note that the final page of _output_ is *not* printed, but returned
	# instead.  This is to support any special handling for the final sequence.
	# 
	def page_print( output )
		lines = output.scan(/[^\n]*\n?/)
		while lines.size > @page_at
			@output.puts lines.slice!(0...@page_at).join
			@output.puts
			ask("-- press enter/return to continue -- ")
			@output.puts
		end
		return lines.join
	end
	
	#
	# Wrap a sequence of _lines_ at _wrap_at_ characters per line.  Existing
	# newlines will not be affected by this process, but additional newlines
	# may be added.
	#
	def wrap( lines )
		wrapped = [ ]
		lines.each do |line|
			while line =~ /([^\n]{#{@wrap_at + 1},})/
				search = $1.dup
				replace = $1.dup
				if index = replace.rindex(" ", @wrap_at)
					replace[index, 1] = "\n"
					replace.sub!(/\n[ \t]+/, "\n")
					line.sub!(search, replace)
				else
					line[@wrap_at, 0] = "\n"
				end
			end
			wrapped << line
		end
		return wrapped.join
	end
end
