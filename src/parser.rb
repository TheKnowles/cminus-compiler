# parser.rb
# Parser for C minus

# Developed with 1.9.3
# Knowles Atchison, Jr.
# Spring 2013
# Compiler Design

require_relative "lexer"

class TreeNode
  attr_accessor :children, :sibling, :val, :tac_str
  attr_reader :line_num
  def initialize(line_num)
    @children = Array.new(3, nil)
    @sibling = nil
    @val = ""
    @line_num = line_num
    @tac_str = ""
  end
end

#modified to define a var_type for input/output functions
class StatementNode < TreeNode
  attr_reader :type, :var_type
  attr_accessor :scope
  @@flavors = [:if_s, :assign_s, :while_s, :input_s, :output_s, :return_s]
  def initialize(type, line_num)
    super(line_num)
    @type = type
    if @type == :input_s then @var_type = :int
    else @var_type = :void end
  end

  def to_s
    "Statement Node: #{@type} line: #{@line_num} scope: #{@scope}"
  end
end

class ExpressionNode < TreeNode
  attr_reader :type
  attr_accessor :var_type
  @@flavors = [:op_exp, :const_exp, :id_exp, :int]
  def initialize(type, line_num)
    super(line_num)
    @type = type
    @var_type = nil
  end
  
  def to_s
    "Expression Node: #{@type} #{@val} #{@var_type} line: #{@line_num}"
  end
end

class FunctionNode < TreeNode
  attr_reader :type
  attr_accessor :var_type
  attr_accessor :var_name
  attr_accessor :is_declaration

  def initialize(line_num)
    super(line_num)
    @type = :function
    @is_declaration = false #default to false, let the func_dec instances declare they are a new var dec
  end

  def to_s
    "Function: #{@var_type} #{@var_name}() line: #{@line_num}"
  end
end

class VariableNode < TreeNode
  attr_reader :type
  attr_accessor :var_type
  attr_accessor :var_name
  attr_accessor :is_arr
  attr_accessor :is_call
  attr_accessor :is_declaration
  attr_accessor :scope

  def initialize(line_num)
    super(line_num)
    @type = :variable
    @is_declaration = false #default to false, let the var_dec instances declare they are a new var dec
    @is_call = false #let the function calls set this
  end

  def to_s
    (@is_call) ?  "Function call: #{@var_type} #{@var_name} line: #{@line_num}" :
    (@is_arr) ? "Variable: #{@var_type} #{@var_name}[] line: #{@line_num} scope: #{@scope}" : 
               "Variable: #{@var_type} #{@var_name} line: #{@line_num} scope: #{@scope}"
  end
end

class Parser
  def initialize(debug=false)
    @debug = debug
    @cur_tok = nil
    @temp_type_tok = nil
    @temp_id_tok = nil
  end

  def dec_list
    t = dec
    p = t
    while @cur_tok.symbol != :endfile
      q = dec
      if q != nil
        if t == nil then t = p = q
        else
          p.sibling = q
          p = q 
        end
      end
    end #while
    t
  end

  def dec
    t = nil
    #var or func
    case @cur_tok.symbol
      when :int, :void
        @temp_type_tok = @cur_tok
        @cur_tok = @lexer.get_token
        @temp_id_tok = @cur_tok
        match((@cur_tok.symbol == :main) ? :main : :id) #match either a function name or main or a variable name
        if @cur_tok.symbol == :lparen 
          t = func_dec
        elsif @cur_tok.symbol == :semi or @cur_tok.symbol == :larr
          t = VariableNode.new(@cur_tok.line_num)
          t.var_type = @temp_type_tok.symbol
          t.var_name = @temp_id_tok.str
          t.val = t.var_name
          t.is_declaration = true
          t.scope = "global"
          if @cur_tok.symbol == :semi
             match(:semi)
          else
            t.is_arr = true
            match(:larr)
            t.children[0] = ExpressionNode.new(:const_exp, @cur_tok.line_num)
            t.children[0].val = @cur_tok.str
            match(:num)
            match(:rarr)
            match(:semi)
          end
        else puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected variable/function declaration"
        end
      else puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected type-specifier"
    end
    t
  end

  def func_dec
    t = FunctionNode.new(@cur_tok.line_num)
    t.var_type = @temp_type_tok.symbol
    t.var_name = @temp_id_tok.str
    t.val = t.var_name
    t.is_declaration = true
    match(:lparen)
    #this was changed to aid in scope checks in the semantic analyzer
    t.children[0] = params("#{t.var_name} parameter")
    match(:rparen)
    t.children[1] = compound_stmt(t.var_name)
    t
  end

  def var_dec(scope) #generally recursively called for n number of declarations see local_dec
    t = nil
    if @cur_tok.symbol == :int or @cur_tok.symbol == :void
      t = VariableNode.new(@cur_tok.line_num)
      t.var_type = @cur_tok.symbol
      @cur_tok = @lexer.get_token #just move past don't bother matching int/void
      t.var_name = @cur_tok.str
      t.is_declaration = true
      t.val = t.var_name
      t.scope = scope
      match(:id)
      if @cur_tok.symbol == :semi then match(:semi)
      elsif @cur_tok.symbol == :larr
        t.is_arr = true
        match(:larr)
        t.children[0] = ExpressionNode.new(:const_exp, @cur_tok.line_num)
        t.children[0].val = @cur_tok.str
        match(:num)
        match(:rarr)
        match(:semi)
      else
        puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected semicolon or array []"
      end # single id or array variable
    else
      #having an empty var_dec block is valid, so don't throw an error
      #puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected type-specifier"
    end #int/void check
    t
  end

  def params(scope)
     if @cur_tok.symbol == :void
       match(:void)
       return nil #don't bother creating a node for void
     end
     t = param_list(scope)
     t
  end

  def param_list(scope) #also does param at the moment
    top = param(scope)
    t = top
    while true
      if @cur_tok.symbol != :comma then break
      else match(:comma) end
      t.sibling = param(scope) #correctly does elements in order
      t = t.sibling
    end #while
    top
  end

  def param(scope)
    t = nil
    if @cur_tok.symbol == :int or @cur_tok.symbol == :void
      t = VariableNode.new(@cur_tok.line_num)
      t.var_type = @cur_tok.symbol
      if @cur_tok.symbol == :int then match(:int)
      else match(:void) end
      t.var_name = @cur_tok.str
      t.val = t.var_name
      t.scope = scope
      t.is_declaration = true
      match(:id) #this is the param part
      if @cur_tok.symbol == :larr
        t.is_arr = true
        match(:larr)
        match(:rarr)
      end
    else
      puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected type-specifier"
    end
   t
  end

  def compound_stmt(scope)
    match(:lbracket)
    top = local_declarations(scope)
    t = top
    if t != nil
      while t and t.sibling #avoid overwriting any local dec with statement lists
        t = t.sibling 
      end
      t.sibling = statement_list(scope) #local decs are optional
    else top = statement_list(scope) end # if this is also nil, function is just empty
    match(:rbracket)
    top
  end

  def local_declarations(scope)
    top = var_dec(scope)
    t = top
    while true
      if @cur_tok.symbol != :int and @cur_tok.symbol != :void then break end
      if t != nil 
        t.sibling = var_dec(scope)
        t = t.sibling
      end
    end
    top
  end

  def statement_list(scope)
    top = statement(scope)
    t = top
    while true
      if @cur_tok.symbol == :rbracket then break end
      if t != nil
        t.sibling = statement(scope)
        t = t.sibling
      end
    end
    top
  end

  def statement(scope)
    t = case @cur_tok.symbol
      when :lbracket                             then compound_stmt(scope)
      when :if                                   then selection_stmt(scope)
      when :while                                then iteration_stmt(scope)
      when :return                               then return_stmt(scope)
      when :rbracket                             then nil
      else
        if probable_expression?(@cur_tok.symbol) then expression_stmt(scope)
        else 
          puts "Unexpected token encountered -> #{@cur_tok.to_s} ## expected valid statement type"
          nil
        end
    end
    t
  end

  #this is to see if the next token is likely an expression
  #since an exp can be ver = exp, or a simple exp so check the token and
  #see if it's the "beginning" of an expression so control returns properly
  def probable_expression?(symbol)
    symbol == :id or symbol == :lparen or 
    symbol == :num or symbol == :semi or
    symbol == :input or symbol == :output
  end

  def expression_stmt(scope)
    t = nil
    if @cur_tok.symbol == :semi then match(:semi)
    else
      t = expression(scope)
      match(:semi)
    end
    t
  end

  #changing assignment from op to assign statement node
  def expression(scope)
    t = simple_exp(scope) #let simple get the var for us to avoid lookahead
    if @cur_tok.symbol == :assign
      p = ExpressionNode.new(:op_exp, @cur_tok.line_num)
      p.val = @cur_tok.str
      match(:assign)
      p.children[0] = t
      t = p
      t.children[1] = expression(scope)
    end
    t
  end

  def var(scope) #no type identifier: either var or var[exp]
    t = VariableNode.new(@cur_tok.line_num)
    t.var_name = @cur_tok.str
    t.val = t.var_name
    t.scope = scope
    match(:id)
    if @cur_tok.symbol == :larr
      t.is_arr = true
      match(:larr)
      t.children[0] = expression(scope)
      match(:rarr)
    end
    t
  end

  def simple_exp(scope)
    top = additive_exp(scope)
    while true
      if not relop?(@cur_tok.symbol) then break
      else
        p = ExpressionNode.new(:op_exp, @cur_tok.line_num)
        p.val = @cur_tok.str
        p.children[0] = top
        @cur_tok = @lexer.get_token 
        p.children[1] = additive_exp(scope)
        top = p
      end
    end
    top
  end

  def relop?(symbol)
    symbol == :eq or symbol == :noteq or symbol == :lt or
    symbol == :lteq or symbol == :gt or symbol == :gteq
  end
  #var_type added to additive and term to facilitate function call parameter checking in the symbol table
  #it wasn't added until type checking and by that time the symbol table was wrong
  def additive_exp(scope)
    top = term(scope)
    while true
      if @cur_tok.symbol != :plus and @cur_tok.symbol != :minus then break
      else 
        p = ExpressionNode.new(:op_exp, @cur_tok.line_num)
        p.val = @cur_tok.str
        p.var_type = :int #added here
        p.children[0] = top
        match((@cur_tok.symbol == :plus)? :plus : :minus)
        top = p
        top.children[1] = term(scope)
      end
    end
    top
  end

  def term(scope)
    top = factor(scope)
    while true
      if @cur_tok.symbol != :times and @cur_tok.symbol != :over then break
      else
        p = ExpressionNode.new(:op_exp, @cur_tok.line_num)
        p.val = @cur_tok.str
        p.var_type = :int # and added here
        p.children[0] = top
        match((@cur_tok.symbol == :times)? :times : :over)
        top = p
        top.children[1] = factor(scope)
      end
    end
    top
  end

  def factor(scope)
    t = nil
    if @cur_tok.symbol == :lparen
      match(:lparen)
      t = expression(scope)
      match(:rparen)
    elsif @cur_tok.symbol == :num
      t = ExpressionNode.new(:const_exp, @cur_tok.line_num)
      t.var_type = :int
      t.val = @cur_tok.str
      match(:num)
    elsif @cur_tok.symbol == :id
      t = var(scope)
      if @cur_tok.symbol == :lparen #is a call ID (args)
        match(:lparen)
        t.is_call = true
        t.children[0] = args(scope)
        match(:rparen)
      end
    elsif @cur_tok.symbol == :input or @cur_tok.symbol == :output
      t = StatementNode.new((@cur_tok.symbol == :input) ? :input_s : :output_s, @cur_tok.line_num)
      match((@cur_tok.symbol == :input) ? :input : :output )
      match(:lparen)
      t.children[0] = args(scope)
      match(:rparen)
    end
    t
  end

  def args(scope)
    args_list(scope)
  end

  def args_list(scope)
    top = expression(scope)
    t = top
    while true
      if @cur_tok.symbol == :comma then match(:comma) end
      if @cur_tok.symbol == :rparen then break end #assume no (exp) factor as arguments
      t.sibling = expression(scope)
      t = t.sibling
    end
    top
  end

  def selection_stmt(scope)
    t = StatementNode.new(:if_s, @cur_tok.line_num)
    match(:if)
    match(:lparen)
    t.children[0] = expression(scope)
    match(:rparen)
    t.children[1] = statement(scope)
    if @cur_tok.symbol == :else
      match(:else)
      t.children[2] = statement(scope)
    end
    t
  end

  def iteration_stmt(scope)
    t = StatementNode.new(:while_s, @cur_tok.line_num)
    match(:while)
    match(:lparen)
    t.children[0] = expression(scope)
    match(:rparen)
    t.children[1] = statement(scope)
    t
  end

  def return_stmt(scope)
    t = StatementNode.new(:return_s, @cur_tok.line_num)
    t.scope = scope
    match(:return)
    if @cur_tok.symbol == :semi then match(:semi)
    else
      t.children[0] = expression(scope)
      match(:semi)
    end
    t
  end

  def match(expected_token_symbol)
    if @cur_tok.symbol == expected_token_symbol then
      @cur_tok = @lexer.get_token
    else
      puts "match: Unexpected token encountered -> #{@cur_tok.to_s} ## expected #{expected_token_symbol}"
      if @debug then puts caller end
    end
  end

  def parse(source_str)
    if @debug then puts "Parsing source string..." end
    @lexer = Lexer.new(source_str, @debug)
    @cur_tok = @lexer.get_token
    t = dec_list
    if @cur_tok.symbol != :endfile then puts "ERROR, code ends before file does" end
    t
  end
end
