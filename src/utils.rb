#utils.rb
# A collection of utils for the compiler
# Also does semantic analysis

# Developed with 1.9.3
# Knowles Atchison, Jr.
# Spring 2013
# Compiler Design

require_relative "parser"

#Moved from a class variable to an entire class
#One to three symbol tables to make variable usage much easier
#if any usage line no is less than the declared line, error
#if in usage, but not in declared, error
#so on and so forth

#Info classes are put into the symbol table maps
#essentially a copy of pertinent bits from the AST nodes
#probably could do with less dupe, but w/e
class VariableInfo
  attr_reader :name, :type, :mem_loc, :line_num, :is_arr, :scope
  attr_accessor :arr_size
  def initialize(name, type, mem_loc, line_num, is_arr, scope)
    @name = name
    @type = type
    @mem_loc = mem_loc
    @line_num = []
    @line_num << line_num
    @is_arr = is_arr
    @scope = scope
    @arr_size = nil #default to nil, ignored if not an array
  end

  def to_s
    (@is_arr) ? "VarInfo: #{@name} #{@type}[#{@arr_size}] #{@mem_loc} #{@line_num} scope: #{@scope}" :
                "VarInfo: #{@name} #{@type} #{@mem_loc} #{@line_num}   scope: #{@scope}"
  end
end

#uses an expression to subscript an array, whereas dec uses a number to indicate size, no var size arrays
class VarUsageInfo < VariableInfo
  attr_reader :name, :line_num, :is_arr, :scope
  attr_accessor :index, :is_call, :params
  def initialize(name, line_num, is_arr, scope)
    @name = name
    @line_num = Hash.new
    @line_num[line_num] = scope
    @is_arr = is_arr
    @is_call = false #default for regular vars, set for functions
    @params = Hash.new {|hash, key|
      hash[key] = []
    }
    @scope = scope
    @index = Hash.new 
  end

  def to_s
    (@is_call)? "VarInfo: #{@name} #{@type} params: #{@params} #{@mem_loc} #{@line_num}" : 
    (@is_arr) ? "VarInfo: #{@name} #{@type}[#{@index}] #{@mem_loc} #{@line_num}" :
                "VarInfo: #{@name} #{@type} #{@mem_loc} #{@line_num}"
  end
end

class FunctionInfo
  attr_reader :name, :type, :mem_loc, :line_num, :scope
  attr_accessor :params
  def initialize(name, type, mem_loc, line_num)
    @name = name
    @type = type
    @mem_loc = mem_loc
    @line_num = []
    @line_num << line_num
    @scope = "global"
    @params = []
  end

  def to_s
    "FuncInfo: #{@name} #{@type} #{@mem_loc} #{@line_num} params: #{@params} scope: #{@scope}"
  end
end

class SymbolTable
  @@mem_loc = 0
  attr_accessor :var_dec_table
  attr_accessor :func_dec_table
  attr_accessor :var_usage_table
  def initialize
    #removed magic, needed a little more fine grained control over info obj creation, see below in insert_node
    @var_dec_table = Hash.new
    @func_dec_table = Hash.new
    @var_usage_table = Hash.new
  end

  def print
    puts "Declared variables [name type mem_loc [line_declared] scope]"
    @var_dec_table.each do |x|
      puts "#{x[0]} \t\t #{x[1]}"
    end
    puts "Declared functions [name type mem_loc [line_declared] [params] scope]"
    @func_dec_table.each do |x|
      puts "#{x[0]} \t\t #{x[1]}"
    end
    puts "Variable/func usage [name [arr indexes] {line_num => scope}]"
    @var_usage_table.each do |x|
      puts "#{x[0]} \t\t #{x[1]}"
    end
  end
end

class Utils
  @@mem_loc = 0
  @@error = false
  def initialize(debug=false)
    @@sym_table_obj = SymbolTable.new
    @debug = debug
  end

  def error?
    @@error
  end

  def print_tree(tree, spaces = 0)
    while tree != nil and tree.kind_of?(TreeNode) #getting endfile Token node in the tree for some reason
      (0..spaces).each {|x| printf " "}
      case tree.type
        when :if_s                   then puts "If"
        when :while_s                then puts "While"
        when :assign_s               then puts "Assign to: #{tree.val}"
        when :input_s                then puts "Input"
        when :output_s               then puts "Output"
        when :op_exp                 then puts "Op #{tree.val}"
        when :const_exp              then puts "Const #{tree.val}"
        when :id_exp                 then puts "Id #{tree.val}"
        when :function, :variable    then puts "#{tree}"
        when :return_s               then puts "return"
        else puts "Unknown node kind(#{tree.type}) [should never happen]"
      end
      tree.children.each do |child|
        print_tree(child, spaces + 2)
      end
      tree = tree.sibling
    end
  end

  #preorder walk of the tree
  def build_symbol_table(tree)
    if @debug then puts "Building symbol table..." end
    traverse(tree, @@insert_node, @@null_op)
    if @debug then print_sym_table end
  end

  #postorder walk of the tree
  def check_types(tree)
    if @debug then puts "Checking types..." end
    traverse(tree, @@null_op, @@check_node)
    if @debug then puts "Checking misc. semantics..." end
    scope_check
    parameter_check
    main_check
  end

  #use str value rather than symbol, which we don't have any more for expression nodes
  def self.relop?(symbol)
    symbol == "==" or symbol == "!=" or symbol == "<" or
    symbol == "<=" or symbol == ">" or symbol == ">="
  end

private
  def print_sym_table
    @@sym_table_obj.print
  end

  #undefined variables/functions will be handled in check_node
  #here, look for variable usage before declaration
  def scope_check
    @@sym_table_obj.var_usage_table.each do |x|
      dec = @@sym_table_obj.var_dec_table[x[0]] 
      if dec == nil then dec = @@sym_table_obj.func_dec_table[x[0]] end
      if dec != nil
        x[1].line_num.each do |line|
          if line[0] < dec.line_num[0] #check line number of definition to usage
             @@error_msg_only.call("ERROR #{dec.name} used on line #{line[0]} before definition on line #{dec.line_num[0]}")
             #don't break, report all usage before definition
          end
        end
      end
    end
  end

  #verify that function calls have the correct number and type of parameters
  #iterate through all variables in usage table, for each function, check params against declared function, must match
  def parameter_check
    @@sym_table_obj.var_usage_table.each do |x|
      if x[1].is_call
        func_dec = @@sym_table_obj.func_dec_table[x[0]]
        if func_dec != nil
          x[1].params.each do |call|
            if call[1].size != func_dec.params.size
               @@error_msg_only.call("ERROR function call #{x[0]} #{call[0]}: has incorrect parameter number")
            end
            i = 0
            while i < call[1].size
              if call[1][i] != func_dec.params[i]
                @@error_msg_only.call("ERROR function call #{x[0]} #{call[0]}: mismatched parameter " +
                                      "#{i+1} found #{call[1][i]} expected #{func_dec.params[i]}")
              end
              i = i + 1
            end
          end
        else
           @@error_msg_only.call("ERROR called a function that was not declared this is redundant, will probably remove")
        end
      end
    end
  end

  #verify that there is a main function and that it is the LAST function defined (as per the book's semantics)
  def main_check
    main = @@sym_table_obj.func_dec_table["main"]
    if main == nil
      @@error_msg_only.call("ERROR main function required")
      return
    else
      if main.type != :void
        @@error_msg_only.call("ERROR main must be of type void")
      end
    end
    
    @@sym_table_obj.func_dec_table.each do |func|
      if func[1].line_num[0] > main.line_num[0] and func != main
        @@error_msg_only.call("ERROR main must be the last function defined in a source file")
      end
    end
  end

  def traverse(tree, pre, post)
    if tree != nil
      pre.call(tree)
      tree.children.each do |child|
        traverse(child, pre, post)
      end
      post.call(tree)
      traverse(tree.sibling, pre, post)
    end
  end

  #lambdas instead of procs since we want control to return to the calling function
  @@null_op = lambda {|tree| return}
  @@error_msg = lambda {|node, msg| 
    puts "#{node}\t#{msg}"
    @@error = true
  }

  #don't need the node's info for some error types
  @@error_msg_only = lambda { |msg|
    puts msg
    @@error = true
  }

  #for variable and function declarations, hash on the node name and create an info object for it, as we need the information associated with it for
  #lookups when they're used (i.e. var_type)
  #will also take care of multiple/redefinition errors
  @@insert_node = lambda { |tree|
    if (tree.type == :variable)
      #if this is a variable declaration, make a few checks and then create an info object on it
      #if it's an array, add its size to the info object
      if (tree.is_declaration == true)
        if @@sym_table_obj.var_dec_table[tree.var_name] != nil
          if @@sym_table_obj.var_dec_table[tree.var_name].scope == "global"
            puts "WARNING local variable definition shadows global variable [TODO]"
          else #known bug here, need to check for scope differences for declartions, will error out on multiple paramter declared vars on different funcs
            @@error_msg.call(tree, "ERROR variable redefinition, originally at #{@@sym_table_obj.var_dec_table[tree.var_name].line_num}")
          end
        else
          if tree.var_type == :void and tree.is_arr == true 
            @@error_msg_only.call("ERROR void array #{tree.var_name} #{tree.line_num}: makes no sense")
          end
          @@sym_table_obj.var_dec_table[tree.var_name] = VariableInfo.new(tree.var_name, tree.var_type, @@mem_loc, 
                                                                        tree.line_num, tree.is_arr, tree.scope)
          #var declarations as paramters do not give an array size, degrades to a pointer a la C
          if tree.is_arr and not tree.scope.include?("parameter") 
            @@sym_table_obj.var_dec_table[tree.var_name].arr_size = tree.children[0].val.to_i 
          end
          @@mem_loc += 1
        end
      else
        #this is not a variable declaration, just usage, if it doesn't exist add it with initial info
        #if not update seen line numbers
        #if it's an array add some subscript info for each use in both instances
        #if it is a function call, iterate through the parameters and grab their types for a check later
        if @@sym_table_obj.var_usage_table[tree.var_name] == nil
          @@sym_table_obj.var_usage_table[tree.var_name] = VarUsageInfo.new(tree.var_name, tree.line_num, tree.is_arr, tree.scope)
          if tree.is_arr
            @@sym_table_obj.var_usage_table[tree.var_name].index[tree.line_num] = 
                           (tree.children[0].instance_of?(VariableNode)) ? tree.children[0].var_name : tree.children[0].val
          elsif tree.is_call
            func_obj = @@sym_table_obj.var_usage_table[tree.var_name]
            func_obj.is_call = true
            temp = tree.children[0]
            while temp != nil
              func_obj.params[tree.line_num] #no op, create array in magic in class
              if  (temp.instance_of?(VariableNode)) and @@sym_table_obj.var_dec_table[temp.var_name] == nil
                @@error_msg.call(temp, "ERROR attempting to use variable as parameter before definition")
                break
              end
              if (temp.instance_of?(VariableNode))
                func_obj.params[tree.line_num] << @@sym_table_obj.var_dec_table[temp.var_name].type.to_s
                if @@sym_table_obj.var_dec_table[temp.var_name].is_arr then func_obj.params[tree.line_num][-1].concat("[]") end
              else func_obj.params[tree.line_num] << temp.var_type.to_s end
              temp = temp.sibling
            end
          end
        else
          @@sym_table_obj.var_usage_table[tree.var_name].line_num[tree.line_num] = tree.scope
          if tree.is_arr
            @@sym_table_obj.var_usage_table[tree.var_name].index[tree.line_num] = 
                           (tree.children[0].instance_of?(VariableNode)) ? tree.children[0].var_name : tree.children[0].val
          elsif tree.is_call
            func_obj = @@sym_table_obj.var_usage_table[tree.var_name]
            func_obj.is_call = true
            temp = tree.children[0]
            while temp != nil
              func_obj.params[tree.line_num] #no op, create array in magic in class
              if (temp.instance_of?(VariableNode))
                func_obj.params[tree.line_num] << @@sym_table_obj.var_dec_table[temp.var_name].type.to_s
                if @@sym_table_obj.var_dec_table[temp.var_name].is_arr then func_obj.params[tree.line_num][-1].concat("[]") end
              else func_obj.params[tree.line_num] << temp.var_type.to_s end
              temp = temp.sibling
            end
          end
        end
      end
    elsif (tree.type == :function)
      #this is doing essentially the same thing as above except it is for declared functions/function usage
      if (tree.is_declaration == true)
        #C- semantics do not dictate that we have to account for function overloads, therefore any same named function will be
        #treated as if it was a redefinition
        if @@sym_table_obj.func_dec_table[tree.var_name] != nil
          @@error_msg.call(tree, "ERROR funciton redefinition, originally at #{@@sym_table_obj.func_dec_table[tree.var_name].line_num}")
        else
          @@sym_table_obj.func_dec_table[tree.var_name] = FunctionInfo.new(tree.var_name, tree.var_type, @@mem_loc, tree.line_num)
          temp = tree.children[0]
          func_obj = @@sym_table_obj.func_dec_table[tree.var_name]
          while temp != nil
            func_obj.params << temp.var_type.to_s #this works because the function dec has to have variable types
            if temp.is_arr then func_obj.params[-1].concat("[]") end
            temp = temp.sibling
          end
          @@mem_loc += 1
        end
      else
        if @@sym_table_obj.var_usage_table[tree.var_name] == nil
          @@sym_table_obj.var_usage_table[tree.var_name] = VarUsageInfo.new(tree.var_name, tree.line_num, tree.is_arr, tree.scope)
        else
          @@sym_table_obj.var_usage_table[tree.var_name].line_num[tree.line_num] = tree.scope
        end
      end
    end
  } #end insert_node

  #for conditionals, look up variable in dec table and get the type
  @@check_node = lambda { |tree|
    case tree.type
      when :variable, :function
        if (tree.is_declaration == true)
          if (not (tree.var_type == :int or tree.var_type == :void))
            @@error_msg.call(tree, "ERROR variable/function declaration with unsupported type")
          end
        else
          #lookup var_type from dec tables and assign it (needed for operand checks of arithmetic operators below)
          #if it cannot find a matching item in the declaration table then it is undefined
          if tree.is_call == false
            if @@sym_table_obj.var_dec_table[tree.var_name] == nil
              @@error_msg.call(tree, "ERROR variable used but not defined")
            else
              tree.var_type = @@sym_table_obj.var_dec_table[tree.var_name].type
              tree.is_arr = @@sym_table_obj.var_dec_table[tree.var_name].is_arr
            end
          else
            if @@sym_table_obj.func_dec_table[tree.var_name] == nil
              @@error_msg.call(tree, "ERROR function used but not defined")
            else
              tree.var_type = @@sym_table_obj.func_dec_table[tree.var_name].type
            end
          end
        end
      when :op_exp
        #assign bool to if/while, relop checks int to other operation nodes (ones not assigned during parser)
        #added int assignment to additive exp and term to correct the symbol table that is built before this fires
        if Utils.relop?(tree.val) then tree.var_type = :bool
        else tree.var_type = :int end
        #verify arithmetic operations
        if tree.children[0].var_type != :int and tree.children[1].var_type != :int
          @@error_msg.call(tree, "ERROR arithmetic operands not integers")
        end
        #verify that the variable being assigned to is an integer
        if tree.val == "="
          if tree.children[0].var_type != :int
            @@error_msg.call(tree, "ERROR lvalue in assignment not integer")
          end
        end
      when :if_s #if/while need to have a boolean conditional to fire off of
        if tree.children[0].var_type == :int then @@error_msg.call(tree.children[0], "ERROR if test not boolean") end
      when :while_s
        if tree.children[0].var_type == :int then @@error_msg.call(tree.children[0], "ERROR while test not boolean") end #fixed conditional bug here
      when :return_s
        #look up the function the return statement is in and verify that the return type and the function type match
        func_ret = @@sym_table_obj.func_dec_table[tree.scope].type
        if tree.children[0] != nil #an expression is after return (should be int)
          if tree.children[0].var_type != :int
            @@error_msg.call(tree.children[0], "ERROR in function #{tree.scope} #{tree.line_num}: return value must be integer")
          elsif func_ret == :void
            @@error_msg.call(tree.children[0], "ERROR in void function #{tree.scope} #{tree.line_num}: may not return a value")
          end
        else #no child
          if func_ret == :int
            @@error_msg.call(tree.children[0], "ERROR in function #{tree.scope} #{tree.line_num}: return value must be integer")
          end
        end
    end
  } #end check_node
end
