#!/usr/env/ruby

# Developed with 1.9.3
# Knowles Atchison, Jr.
# Spring 2013
# Compiler Design

# to run:
#   command line: ruby main.rb /path/to/file

# all additional srcs in same directory
require_relative "utils"
require_relative "codegen"

class CminusCompiler
  def initialize(filename, debug=false)
    @debug = debug
    @src = load_source(filename)
    @parser = Parser.new(@debug)
    @utils = Utils.new(@debug)
    @out_filename = filename.sub(".c-", ".tm")
    tree = @parser.parse(@src)
    if @debug then @utils.print_tree(tree) end
    @utils.build_symbol_table(tree)
    @utils.check_types(tree)
    unless @utils.error?
      @codegen = CodeGenerator.new(@debug,Utils.class_variable_get(:@@sym_table_obj))
      if @debug then puts "Generating code..." end
      #File.write(@out_filename, @codegen.gen_tm_code(tree))
      @codegen.gen_three_code(tree)
      #if @debug then puts "#{@out_filename} generated." end
    end
  end

  def load_source(filename)
    completeFile = String.new
    if @debug then puts "Loading #{filename}" end
    completeFile = File.read(filename)
    if @debug then puts completeFile end
    #add a null terminator to simulate eof flag
    completeFile << "\0"
    completeFile
  end
end

#driver, defaults to debug
if ARGV.length == 0 then puts "Program usage: ruby main.rb /path/to/file"
else CminusCompiler.new(ARGV[0], true) end
