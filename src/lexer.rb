# lexer.rb
# Scanner used by the parser for the C- language

# Developed with 1.9.3
# Knowles Atchison, Jr.
# Spring 2013
# Compiler Design

#ruby string/char to symbol map for token table
$token_table = {
  "\0" => :endfile, #requires double quotes to map correctly in code below
  "="  => :assign,
  "==" => :eq,
  "!=" => :noteq,
  "<"  => :lt,
  "<=" => :lteq,
  ">"  => :gt,
  ">=" => :gteq,
  "+"  => :plus,
  "-"  => :minus,
  "*"  => :times,
  "/"  => :over,
  "("  => :lparen,
  ")"  => :rparen,
  "{"  => :lbracket,
  "}"  => :rbracket,
  ";"  => :semi,
  ","  => :comma,
  "["  => :larr,
  "]"  => :rarr,
  "/*"  => :commstart,
  "*/"  => :commend,
  nil  => :error
}

#mapping to go from reserved keyword to useful symbol
$reserved_words = {
  "if"     => :if,
  "else"   => :else,
  "int"    => :int,
  "return" => :return,
  "void"   => :void,
  "main"   => :main,
  "input"  => :input,
  "output" => :output,
  "while"  => :while
}

class Token
  attr_reader :str, :reserved, :line_num
  def initialize(symbol, str, line_num)
    @symbol = symbol
    @str = str
    @reserved = $reserved_words[str]
    @line_num = line_num
  end

  #normalize: if it's a reserved keyword map to appropriate symbol, otherwise use symbol derived from scanner 
  def symbol
    (@reserved) ? @reserved : @symbol
  end

  def reserved?
    @reserved
  end

  def to_s
    (@reserved) ? "Line #{@line_num}: Reserved keyword: #{@str}" : "Line #{@line_num}: #{@symbol.to_s} #{@str}"
  end
end

class Lexer
   attr_reader :line_num
   #scanner states
  :start
  :in_comment
  :in_num
  :in_id
  :done
  def initialize(source_str, debug = false)
    @debug = false #overwrite for semantic testing return afterwards
    @cur_pos = 0
    @source = source_str
    @line_num = 1
  end

  def get_token
    cur_state, cur_token, cur_token_str = :start, nil, ""
    while cur_state != :done
      save, cur_char = true, @source[@cur_pos]
      case cur_state
        when :start 
          if numeric?(cur_char)            then cur_state = :in_num
          elsif letter?(cur_char)          then cur_state = :in_id
          elsif whitespace?(cur_char)      then save = false
          elsif cur_char == '/'
            if @source[@cur_pos + 1] == '*'
              save, cur_state = false, :in_comment
              @cur_pos += 1
            else cur_state, cur_token = :done, $token_table[cur_char] end
          elsif cur_char == '=' and @source[@cur_pos + 1] == '='
            cur_token_str << cur_char
            @cur_pos += 1
            cur_token, cur_state, cur_char = :eq, :done, @source[@cur_pos]
          elsif cur_char == '!' and @source[@cur_pos + 1] == '='
            cur_token_str << cur_char
            @cur_pos += 1
            cur_token, cur_state, cur_char = :noteq, :done, @source[@cur_pos]
          elsif cur_char == '<' and @source[@cur_pos + 1] == '='
            cur_token_str << cur_char
            @cur_pos += 1
            cur_token, cur_state, cur_char = :lteq, :done, @source[@cur_pos]
          elsif cur_char == '>' and @source[@cur_pos + 1] == '='
            cur_token_str << cur_char
            @cur_pos += 1
            cur_token, cur_state, cur_char = :gteq, :done, @source[@cur_pos]
          else  cur_state, cur_token = :done, $token_table[cur_char] end
        when :in_num
          if not numeric?(cur_char)
            @cur_pos -= 1
            cur_state, cur_token, save = :done, :num, false
          end
        when :in_id
          if not letter?(cur_char)
            @cur_pos -= 1
            cur_state, cur_token, save = :done, :id, false
          end
        when :in_comment
          save = false
          if cur_char == "\n" then @line_num += 1 end
          if cur_char == '\0'
            cur_state, cur_token = :done, :endfile
          elsif cur_char == '/' and @source[@cur_pos + 1] == '*'
            cur_token == :error
            @cur_pos += 1
            puts "Error, line #{@line_num}: Nested comments are not allowed"
          elsif cur_char == '*' and @source[@cur_pos + 1] == '/'
              cur_state = :start
              @cur_pos += 1
          end
        else
          puts "Error, #{cur_state} state entered [this should never happen]"
          exit
      end #case
      if save and cur_token != :error then cur_token_str << cur_char end
      @cur_pos += 1
    end #while cur_state
    if @debug then puts "\tDEBUG token: #{cur_token_str} line: #{@line_num}" end
    return Token.new(cur_token, cur_token_str, @line_num)
  end

  def letter?(char)
    char =~ /[[:alpha:]]/
  end

  def numeric?(char)
    char =~ /[[:digit:]]/
  end

  def whitespace?(char)
    #assume non "\r\n" line endings for now
    if char == "\n" then @line_num += 1 end
    char =~ /\s/
  end
end
