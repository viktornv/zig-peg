const std = @import("std");
const peg = @import("peg");

// XML 1.0 practical full-syntax parser (well-formedness level).
// Covers:
// - XML declaration, doctype, processing instructions, comments
// - start/end/empty elements, attributes, references
// - CDATA and mixed content
// Notes:
// - Name matching between start/end tags is not validated by PEG alone.
const xml = peg.compile(
    \\document      <- _ws prolog? element misc*
    \\@squashed prolog <- xml_decl? misc* doctype? misc*
    \\xml_decl      <- '<?xml' _req_ws version_info (_req_ws encoding_decl)? (_req_ws standalone_decl)? _ws '?>'
    \\@squashed version_info <- 'version' _eq version_num
    \\version_num   <- '"' '1.' [0-9]+ '"' / '\'' '1.' [0-9]+ '\''
    \\@squashed encoding_decl <- 'encoding' _eq enc_name_q
    \\@squashed enc_name_q <- '"' enc_name '"' / '\'' enc_name '\''
    \\enc_name      <- [A-Za-z] [A-Za-z0-9._\-]*
    \\@squashed standalone_decl <- 'standalone' _eq standalone_q
    \\@squashed standalone_q <- '"' ('yes' / 'no') '"' / '\'' ('yes' / 'no') '\''
    \\
    \\doctype       <- '<!DOCTYPE' _req_ws name (_req_ws external_id)? (_ws '[' _ws int_subset? _ws ']')? _ws '>'
    \\@squashed external_id <- ('SYSTEM' _req_ws system_literal) / ('PUBLIC' _req_ws pubid_literal _req_ws system_literal)
    \\system_literal <- '"' [^"]* '"' / '\'' [^']* '\''
    \\pubid_literal <- '"' [^"]* '"' / '\'' [^']* '\''
    \\@squashed int_subset <- (markup_decl / pi / comment / _s)*
    \\@squashed markup_decl <- element_decl / attlist_decl / entity_decl / notation_decl
    \\element_decl  <- '<!ELEMENT' _req_ws name _req_ws [^>]+ '>'
    \\attlist_decl  <- '<!ATTLIST' _req_ws name _req_ws [^>]+ '>'
    \\entity_decl   <- '<!ENTITY' _req_ws [^>]+ '>'
    \\notation_decl <- '<!NOTATION' _req_ws [^>]+ '>'
    \\
    \\element       <- empty_elem_tag / start_tag content end_tag
    \\start_tag     <- '<' name (_req_ws attribute)* _ws '>'
    \\empty_elem_tag <- '<' name (_req_ws attribute)* _ws '/>'
    \\end_tag       <- '</' name _ws '>'
    \\attribute     <- name _eq attr_value
    \\attr_value    <- '"' _att_dq* '"' / '\'' _att_sq* '\''
    \\@silent _att_dq       <- reference / [^<&"]
    \\@silent _att_sq       <- reference / [^<&']
    \\
    \\@squashed content <- (char_data? ((element / reference / cdata / pi / comment) char_data?)*)?
    \\char_data     <- [^<&]+
    \\cdata         <- '<![CDATA[' _cdata_char* ']]>'
    \\@silent _cdata_char   <- !']]>' .
    \\comment       <- '<!--' _comment_char* '-->'
    \\@silent _comment_char <- !'--' .
    \\pi            <- '<?' pi_target (_req_ws pi_body)? '?>'
    \\pi_target     <- !'xml'i name
    \\pi_body       <- (!'?>' .)+
    \\@squashed reference <- entity_ref / char_ref
    \\entity_ref    <- '&' name ';'
    \\char_ref      <- '&#' [0-9]+ ';' / '&#x' [0-9A-Fa-f]+ ';'
    \\
    \\@squashed misc <- comment / pi / _s
    \\name         <- [A-Za-z_:] [A-Za-z0-9_.:\-]*
    \\@silent _eq          <- _ws '=' _ws
    \\@silent _req_ws      <- [ \t\r\n]+
    \\@silent _s            <- [ \t\r\n]+
    \\@silent _ws           <- [ \t\r\n]*
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try xml.parse(arena.allocator(), "document", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (xml.parse(arena.allocator(), "document", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "xml basic elements" {
    try expectParseAll("<root/>");
    try expectParseAll("<root></root>");
    try expectParseAll("<root><a/><b/></root>");
    try expectParseAll("<root><a>text</a><b>more</b></root>");
}

test "xml attributes and namespaces" {
    try expectParseAll("<root id=\"42\" class='main'/>");
    try expectParseAll("<ns:root xmlns:ns=\"urn:test\" ns:attr=\"x\"></ns:root>");
    try expectParseAll("<r a=\"1 &amp; 2\" b='&#x41;'/>");
}

test "xml declaration and prolog" {
    try expectParseAll("<?xml version=\"1.0\"?><root/>");
    try expectParseAll("<?xml version='1.1' encoding=\"UTF-8\" standalone='yes'?><root/>");
    try expectParseAll("<?xml version=\"1.0\"?>\n<!--header-->\n<?app mode=\"fast\"?>\n<root/>");
}

test "xml doctype and internal subset" {
    try expectParseAll(
        \\<?xml version="1.0"?>
        \\<!DOCTYPE note [
        \\  <!ELEMENT note (to,from,body)>
        \\  <!ATTLIST note id CDATA #IMPLIED>
        \\  <!ENTITY writer "Alice">
        \\  <!NOTATION png SYSTEM "image/png">
        \\]>
        \\<note id="n1"><to>Bob</to><from>&writer;</from><body>Hello</body></note>
    );
}

test "xml mixed content cdata and comments" {
    try expectParseAll("<root>Hello <![CDATA[<xml>&stuff]]> world</root>");
    try expectParseAll("<root><!-- c --><a/>text<?pi ok?></root>");
    try expectParseAll("<root>start &lt;middle&gt; &#65; end</root>");
}

test "xml invalid cases" {
    try expectFail("");
    try expectFail("root");
    try expectFail("<root>");
    try expectFail("</root>");
    try expectFail("<root attr=42/>");
    try expectFail("<root><a></root>");
    try expectFail("<root><!-- bad -- comment --></root>");
    try expectFail("<?xml version=\"1.0\"?><root></root> trailing");
}

test "xml tree structure smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input =
        "<book id=\"b1\"><title>zig-peg</title><meta><k>lang</k><v>zig</v></meta></book>";
    const res = try xml.parse(arena.allocator(), "document", input);

    try std.testing.expectEqualStrings("document", res.node.tag);
    try std.testing.expect(countTag(res.node, "element") >= 4);
    try std.testing.expect(countTag(res.node, "attribute") >= 1);
    try std.testing.expect(countTag(res.node, "name") >= 6);
}
