# codegen.rb
# Code Generator for the C-

# Developed with 1.9.3
# Knowles Atchison, Jr.
# Spring 2013
# Compiler Design

class CodeGenerator
  def initialize(debug=false, sym_table)
    @debug = debug
    @buffer = String.new
    @sym_table = sym_table
    @temp_num = 0
    @label_num = 0
    @tac_tree = []
    @var_temp_table = Hash.new
  end

  #generate three address code to illustrate expected assembly flow
  def gen_three_code(tree)
    gen_test(tree)
    clean_up_tac(tree)
    build_tac_tree(tree)
    if @debug then print_tac_tree end
    optimize(tree)
    if @debug
      puts "Optimized code..."
      print_tac_tree 
    end
    #puts @var_temp_table
  end

private
  
  def reset_temps
    @temp_num = 0
    @label_num = 0
  end

  def print_tac_tree
    @tac_tree.each do |line|
      puts line
    end
  end

  #go through the lineraization of the tree and see what can be done
  #tree is passed in to make the node nil and then the tac_tree is recreated
  #this is cleaner than trying to lex the tac strs and would leave labels and such in which are meaningless
  def optimize(tree)
    #look for conditionals whose blocks can be removed due to constant assignment that would ignore a block
    #optimization "dead code removal"
    cur_line = 0
    @tac_tree.each do |line|
      if line.scan(/if_false/).first != nil
        prev = @tac_tree[cur_line-1]
        result = prev.split(' = ') #avoid spliting on '=='
        temp = result[0]
        #lookup what temp is assigned to
        relop = @var_temp_table[temp]
        elements = relop.split(' ')
        var = elements[0]
        op = elements[1]
        cond = elements[2]
        const_val = @var_temp_table[var]
        if const_val =~ /[[:digit:]]/
          #a const assignment to a variable, we can now test relop to avoid block in its entirity
          test = case op
                   when "==" then const_val.to_i == cond.to_i
                   when "<=" then const_val.to_i <= cond.to_i
                   when ">=" then const_val.to_i >= cond.to_i
                   when "<" then const_val.to_i < cond.to_i
                   when ">" then const_val.to_i > cond.to_i
                 end
          if test == false #the block can be optimized out
            block_removal(tree, line)
          end
        end
      end
      cur_line += 1
    end
  end

  def block_removal(tree, line)
    root = prev_node = tree
    while tree != nil
      tree.children.each do |child|
        block_removal(child, line)
      end
      if tree.tac_str == line
        #destroy this node and assign prev node to its sibling
        prev_node.sibling = tree.sibling
        reset_temps
        @tac_tree.clear
        clear_tac(root)
        gen_test(root)
        clean_up_tac(root)
        build_tac_tree(root)
        break
      end
      prev_node = tree
      tree = tree.sibling
    end
  end

  def clear_tac(tree)
    while tree != nil
      tree.children.each do |child|
        clear_tac(child)
      end
    tree.tac_str = ""
    tree = tree.sibling
    end
  end

  #correct temp variable created for if/while conditionals
  def clean_up_tac(tree)
    while tree != nil
      tree.children.each do |child|
        clean_up_tac(child)
      end
      if tree.type == :if_s or tree.type == :while_s
        #tac str format temp = var relop var
        temp = tree.tac_str.scan(/\[.*\]/)
        new_str = temp.first.gsub!('[',"").gsub!(']',"")
        temp = new_str.split('=')[0]
        tree.tac_str.sub!(/\[.*\]/, temp)
        #clean children string of regex capture helpers
        tree.children[0].tac_str = tree.children[0].tac_str.scan(/\[.*\]/).first.gsub!('[',"").gsub!(']',"")
      end
      tree = tree.sibling
    end
  end

  #iterate through the tree and put into an array, effectively linearizing the tree
  def build_tac_tree(tree)
    while tree != nil
      if is_block_start?(tree.type) and tree.tac_str != nil
        if tree.type == :if_s or tree.type == :while_s
          #puts tree.children[0].tac_str put temp conditional creation ahead of the check
          @tac_tree << tree.children[0].tac_str
        end
        #puts tree.tac_str 
        @tac_tree << tree.tac_str 
      end
      tree.children.each do |child|
        build_tac_tree(child)
      end
      #optimization #1 (tree.type != :variable) gets rid of additional load statements, tm would load on declaration statement 
      if tree.type != :variable and tree.type != :function and not tree.type == :const_exp and 
         not is_block_start?(tree.type) and tree.tac_str != nil and not relop?(tree.val) and tree.type != :input_s
        #puts tree.tac_str
        @tac_tree << tree.tac_str
      end
      tree = tree.sibling
    end
  end

  def is_block_start?(type)
    type == :function or type == :if_s or type == :while_s
  end

  def relop?(symbol)
    symbol == "==" or symbol == "!=" or symbol == "<" or
    symbol == "<=" or symbol == ">" or symbol == ">="
  end

  def new_temp
    @temp_num = @temp_num + 1
    return "t#{@temp_num}"
  end

  def new_label
    @label_num = @label_num + 1
    return "L#{@label_num}"
  end

  #post order traversal, build the tac strings, then post order again to print except for function entry
  def gen_test(tree)
    while tree != nil
      c1,c2, c3 = tree.children[0], tree.children[1], tree.children[2] #else clause
      if c1 != nil then gen_test(c1) end
      if c2 != nil then gen_test(c2) end
      if c3 != nil then gen_test(c3) end
      case tree.type
        when :if_s
          if tree.sibling != nil
            temp = new_label
            tree.tac_str << "if_false #{tree.children[0].tac_str} jmp to #{temp}"
            tree.sibling.tac_str.prepend("#{temp}: ")
          else
            if tree.children[2] != nil #there is an else with this
              temp = new_label
              tree.tac_str << "if_false #{tree.children[0].tac_str} jmp to #{temp}"
              tree.children[2].tac_str.prepend("#{temp}: ")
            else tree.tac_str << "if_false #{tree.children[0].tac_str} jmp bug" end #no sbiling no else stmt, fall through to next instruction
            #known bug here, need to have parent info if there is no sibling, i.e. an if inside an if block with no follow on statements
          end
        when :while_s
          if tree.sibling != nil
            start = new_label
            finish = new_label
            tree.tac_str << "#{start}: if_false #{tree.children[0].tac_str} jmp to #{finish}"
            #iterate to the last statement in the while loop and add a goto start label
            temp = tree.children[1]
            while true
              if temp.sibling == nil then break end
              temp = temp.sibling 
            end
            temp.tac_str << "\ngoto #{start}"
            tree.sibling.tac_str.prepend("#{finish}: ")
          else end
        when :op_exp
          case tree.val
            when "+", "-", "*", "/"
              # get a temporary value/register fill out TAC and then modify node for multiple nested arithmetic expressions
              temp = new_temp
              tree.tac_str << "#{temp} = #{tree.children[0].val} #{tree.val} #{tree.children[1].val}"
              tree.val = temp
              @var_temp_table[temp] = "#{tree.children[0].val} #{tree.val} #{tree.children[1].val}"
            when "="
              tree.tac_str << "#{tree.children[0].tac_str} = #{tree.children[1].tac_str.split[0]}"
              @var_temp_table["#{tree.children[0].tac_str}"] = "#{tree.children[1].tac_str.split[0]}"
            when "<",">","<=",">=", "==", "!="
              temp = new_temp
              tree.tac_str << "[#{temp} = #{tree.children[0].tac_str} #{tree.val} #{tree.children[1].tac_str}]"
              @var_temp_table[temp] = "#{tree.children[0].tac_str} #{tree.val} #{tree.children[1].tac_str}"
          end
        when :variable
            if tree.is_call
              temp = tree.children[0]
              while temp != nil
                tree.tac_str << "arg #{temp.tac_str.split[0]} "
                temp = temp.sibling
              end
              tree.tac_str << "call #{tree.var_name}"
            elsif not tree.is_declaration then tree.tac_str << "#{tree.var_name}" end
        when :function
          tree.tac_str << "entry #{tree.var_name}"
          #add parameters if they exist
          if tree.is_declaration
            if tree.children[0] != nil
              temp = tree.children[0]
              tree.tac_str << "("
              while true
                if temp == nil then break end
                tree.tac_str << " #{temp.val} "
                temp = temp.sibling
              end
              tree.tac_str << ")"
            end
          end
        when :const_exp
          tree.tac_str << "#{tree.val}"
        when :input_s
          tree.tac_str << "input"
        when :output_s
          tree.tac_str << "output ( #{tree.children[0].tac_str} )"
        when :return_s
          tree.tac_str << "return ( #{tree.children[0].tac_str} )"
      end
      tree = tree.sibling
    end
  end
end
