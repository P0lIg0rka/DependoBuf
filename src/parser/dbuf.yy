%skeleton "lalr1.cc"
%require  "3.4"
%header

%defines

%define api.token.raw
%define api.value.type variant

%define api.namespace {dbuf::parser}
%define api.parser.class {Parser}

%code requires{
  #include <parser/ast.h>
  #include <parser/expression.h>

  namespace dbuf::parser {
    class Driver;
    class Lexer;
  }

}

%parse-param { Lexer &scanner }
%parse-param { Driver &driver }

%locations

%define parse.trace
%define parse.error detailed
%define parse.lac full

%code {
  #include <iostream>
  #include <cstdlib>
  #include <fstream>

  #include <parser/driver.hpp>
  #include <parser/ast.h>
  #include <parser/expression.h>

#undef yylex
#define yylex scanner.yylex
}

%define api.token.prefix {TOK_}

%token END 0 "end of file"
%token NL
%token <std::string> LC_IDENTIFIER UC_IDENTIFIER
%token MESSAGE ENUM IMPL SERVICE RPC RETURNS
%token FALSE TRUE
%token
  PLUS "+"
  MINUS "-"
  STAR "*"
  SLASH "/"
;
%token
  AND "&&"
  OR "||"
  BANG "!"
;
%token
  LEFT_PAREN "("
  RIGHT_PAREN ")"
  LEFT_BRACE "{"
  RIGHT_BRACE "}"
;
%token
  COMMA ","
  DOT "."
  COLON ":"
;
%token <double> FLOAT_LITERAL
%token <long long> INT_LITERAL
%token <std::string> STRING_LITERAL

%right ":"
%left "!=" ">=" "<=" "<" "=" ">"
%left "||" "-" "+"
%left "&&" "*" "/"
%right "!"

%start schema

%%

schema : definitions { driver.saveAst(std::move($1)); }

%nterm <AST> definitions;
definitions
  : %empty { $$ = std::move(AST()); }
  | definitions message_definition {
    $$ = std::move($1);
    $$.AddMessage(std::move($2));
  }
  | definitions enum_definition {
    $$ = std::move($1);
    $$.AddEnum(std::move($2));
  }
  | definitions service_definition {
    $$ = std::move($1);
  }
  ;

%nterm <Message> message_definition;
message_definition
  : MESSAGE type_identifier type_dependencies fields_block {
    $$ = Message{.name_=std::move($2)};
    for (auto &type_dependency : $3) {
      $$.AddDependency(std::move(type_dependency));
    }
    for (auto &field : $4) {
      $$.AddField(field);
    }
  }
  | MESSAGE type_identifier fields_block {
    $$ = Message{.name_=std::move($2)};
    for (auto &field : $3) {
      $$.AddField(field);
    }
  }
  ;

%nterm <Enum> enum_definition;
enum_definition
  : dependent_enum { $$ = std::move($1); }
  | independent_enum { $$ = std::move($1); }
  ;

%nterm <Enum> dependent_enum;
dependent_enum
  : ENUM type_identifier type_dependencies dependent_enum_body {
    $$ = std::move($4);
    $$.name_ = $2;
    for (auto &type_dependency : $3) {
      $$.AddDependency(std::move(type_dependency));
    }
  }
  ;

%nterm <Enum> independent_enum;
independent_enum
  : ENUM type_identifier independent_enum_body {
    $$ = Enum{.name_=std::move($2)};
  }
  ;

%nterm <Enum> independent_enum_body;
independent_enum_body
  : constructors_block {
    $$ = Enum{};
    $$.AddOutput(std::move($1));
  }

%nterm <std::vector<TypedVariable>> type_dependencies;
type_dependencies
  : type_dependency {
    $$ = std::vector<TypedVariable>();
    $$.push_back($1);
  }
  | type_dependencies type_dependency {
    $$ = $1;
    $$.push_back($2);
  }
  ;

%nterm <TypedVariable> type_dependency;
type_dependency
  : "(" typed_variable ")" {
    $$ = $2;
  }
  ;

%nterm <Enum> dependent_enum_body;
dependent_enum_body : "{" NL dependent_blocks "}" NL { $$ = std::move($3); };

%nterm <Enum> dependent_blocks;
dependent_blocks
  : %empty {
    $$ = Enum();
  }
  | dependent_blocks pattern_matching IMPL constructors_block {
    $$ = $1;
    $$.AddInput($2);
    $$.AddOutput($4);
  }
  ;

%nterm <std::vector<std::variant<Value, StarValue>>> pattern_matching;
pattern_matching
  : pattern_match {
    $$ = std::vector<std::variant<Value, StarValue>>();
    $$.push_back($1);
  }
  | pattern_matching "," pattern_match {
    $$ = $1;
    $$.push_back($3);
  }
  ;

%nterm <std::variant<Value, StarValue>> pattern_match;
pattern_match
  : STAR {
    $$ = StarValue{};
  }
  | value {
    $$ = $1;
  }
  ;

%nterm <std::vector<Constructor>> constructors_block;
constructors_block
  : "{" NL constructor_declarations "}" NL { $$ = $3; };

%nterm <std::vector<Constructor>> constructor_declarations;
constructor_declarations
  : %empty {
    $$ = std::vector<Constructor>();
  }
  | constructor_declarations constructor_identifier fields_block {
    $$ = $1;
    $$.push_back(Constructor{.name_= $2});
    for (auto &field : $3) {
      $$.back().AddField(field);
    }
  }
  | constructor_declarations constructor_identifier NL {
    $$ = $1;
    $$.push_back(Constructor{.name_=$2});
  }
  ;

%nterm <std::vector<TypedVariable>> fields_block;
fields_block : "{" NL field_declarations "}" NL { $$ = $3; }; ;

%nterm <std::vector<TypedVariable>> field_declarations;
field_declarations
  : %empty {
    $$ = std::vector<TypedVariable>();
  }
  | field_declarations typed_variable NL {
    $$ = $1;
    $$.push_back($2);
  }
  ;

%nterm <TypeExpression> type_expr;
type_expr
  : type_identifier {
    $$ = TypeExpression{$1};
  }
  | type_expr primary {
    $$ = $1;
    $$.type_parameters_.push_back($2);
  }
  ;

%nterm <Expression> expression;
expression
  : expression PLUS expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kPlus, $3};
  }
  | expression MINUS expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kMinus, $3};
  }
  | expression STAR expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kStar, $3};
  }
  | expression SLASH expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kSlash, $3};
  }
  | expression AND expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kAnd, $3};
  }
  | expression OR expression {
    $$ = BinaryExpression{$1, BinaryExpressionType::kOr, $3};
  }
  | type_expr {
    $$ = TypeExpression{$1};
  }
  | MINUS expression {
    $$ = UnaryExpression{UnaryExpressionType::kMinus, $2};
  }
  | BANG expression {
    $$ = UnaryExpression{UnaryExpressionType::kBang, $2};
  }
  | primary {
    $$ = $1;
  }
  ;

%nterm <Expression> primary;
primary
  : value {
    $$ = $1;
  }
  | var_access {
    $$ = $1;
  }
  | "(" expression ")" {
    $$ = $2;
  }
  ;

%nterm <VarAccess> var_access;
var_access
  : var_identifier {
    $$ = VarAccess{$1};
  }
  | var_access "." var_identifier {
    $1.field_identifiers.push_back($3);
    $$ = $1;
  }
  ;

%nterm <Value> value;
value
  : bool_literal { $$ = $1; }
  | float_literal { $$ = $1; }
  | int_literal { $$ = $1; }
  | string_literal { $$ = $1; }
  | constructed_value { $$ = $1; }
  ;

%nterm <Value> bool_literal;
bool_literal
  : FALSE { $$ = Value(ScalarValue<bool>{false}); }
  | TRUE { $$ = Value(ScalarValue<bool>{true}); }
  ;

%nterm <Value> float_literal;
float_literal : FLOAT_LITERAL { $$ = Value(ScalarValue<double>{$1}); } ;

%nterm <Value> int_literal;
int_literal : INT_LITERAL { $$ = Value(ScalarValue<long long>{$1}); };

%nterm <Value> string_literal;
string_literal : STRING_LITERAL { $$ = Value(ScalarValue<std::string>{$1}); };

%nterm <Value> constructed_value;
constructed_value
  : constructor_identifier "{" field_initialization "}" {
    $$ = Value(ConstructedValue{$1, $3});
  }
  ;
%nterm <FieldInitialization> field_initialization;
field_initialization
  : %empty {
    $$ = FieldInitialization();
  }
  | var_identifier COLON expression {
    $$ = FieldInitialization();
    $$.AddField($1, $3);
  }
  | field_initialization "," var_identifier COLON expression {
    $$ = $1;
    $$.AddField($3, $5);
  }
  ;

%nterm <std::string>
  type_identifier
  constructor_identifier
  service_identifier
  var_identifier
  rpc_identifier
;
type_identifier : UC_IDENTIFIER { $$ = std::move($1); };
constructor_identifier : UC_IDENTIFIER { $$ = std::move($1); };
service_identifier : UC_IDENTIFIER { $$ = std::move($1); };
var_identifier : LC_IDENTIFIER { $$ = std::move($1); };
rpc_identifier : LC_IDENTIFIER { $$ = std::move($1); };

service_definition
  : SERVICE service_identifier rpc_block
  ;
rpc_block
  : "{" NL rpc_declarations "}" NL ;
rpc_declarations
  : %empty
  | RPC rpc_identifier "(" arguments ")"
    RETURNS "(" type_expr ")" NL
  ;
arguments
  : %empty
  | typed_variable
  | typed_variable "," arguments
  ;

%nterm <TypedVariable> typed_variable;
typed_variable
  : var_identifier type_expr {
    $$ = TypedVariable{.name_=std::move($1), .type_expression_= $2};
  }

%%

void dbuf::parser::Parser::error(const location_type &l, const std::string &err_message)
{
   std::cerr << "Error: " << err_message << " at " << l << "\n";
}
