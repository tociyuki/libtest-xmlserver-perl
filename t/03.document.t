use strict;
use warnings;
use Test::Base;
use Test::XmlServer::Document;

plan tests => 49;

{
    my($it, $spec);
    sub describe($) { $it = shift }
    sub it($) { $spec = $it . q{ } . shift }
    sub spec() { return $spec }
}

{
    describe 'T::X::Document';

        my $class = 'Test::XmlServer::Document';

    it 'can new';

        ok eval{ $class->can('new') }, spec;

    it 'can find';

        ok eval{ $class->can('find') }, spec;

    it 'can tagname';

        ok eval{ $class->can('tagname') }, spec;

    it 'can attribute';

        ok eval{ $class->can('attribute') }, spec;

    it 'can child_nodes';

        ok eval{ $class->can('child_nodes') }, spec;

    it 'should create an instance';

        ok eval{ $class->new('<html></html>')->isa($class) }, spec;
}

{
    describe 'document';

        my $doc = Test::XmlServer::Document->new(<<'HTML');
<!DOCTYPE html>
<html>
<head>
 <meta encoding="utf-8" />
 <title>SITE NAME</title>
</head>
<body>
 <h1>SITE NAME</h1>
 <ul>
  <li><a href="#ID1">TITLE1</a></li>
  <li><a href="#ID2">TITLE2</a></li>
 </ul>
 <div id="ID1" class="hentry topic">
 <h2><a rel="bookmark" href="permalink1">TITLE1</a></h2>
 <p class="abstract">ABSTRACT1</p>
 <p class="entry-body">CONTENT1</p>
 </div>
 <div id="ID2" class="hentry">
 <h2><a rel="bookmark" href="permalink2">TITLE2</a></h2>
 <p class="abstract">ABSTRACT2</p>
 <p class="entry-body-2">CONTENT2</p>
 </div>
</body>
</html>
HTML

    it 'should find html element';

        my($html) = $doc->find('html');
        ok $html, spec;

    it 'should get tagname of html element';

        is $html->tagname, 'html', spec;

    it 'should get no attribute names for html element';

        is_deeply [$html->attribute], [], spec;

    it 'should get two child nodes for html element';

        is scalar @{$html->child_nodes}, 2, spec;

    it 'should get 1st child as head element';

        is $html->child_nodes->[0]->tagname, 'head', spec;

    it 'should get 2nd child as body element';

        is $html->child_nodes->[1]->tagname, 'body', spec;

    it 'should get meta element';

        my($meta) = $doc->find('meta');
        is $meta->attribute('encoding'), 'utf-8', spec;

    it 'should find four elements';

        my(@link) = $doc->find('a');
        is scalar @link, 4, spec;

    it 'should get ID1 from 1st element';

        is $link[0]->attribute('href'), '#ID1', spec;

    it 'should get ID2 from 2nd element';

        is $link[1]->attribute('href'), '#ID2', spec;

    it 'should get permalink1 from 3rd element';

        is $link[2]->attribute('href'), 'permalink1', spec;

    it 'should get bookmark from 3rd element';

        is $link[2]->attribute('rel'), 'bookmark', spec;

    it 'should get permalink2 from 4th element';

        is $link[3]->attribute('href'), 'permalink2', spec;

    it 'should get bookmark from 4th element';

        is $link[3]->attribute('rel'), 'bookmark', spec;

    it 'should get ID1 element';

        my($id1) = $doc->find('#ID1');
        is $id1->attribute('class'), 'hentry topic', spec;

    it 'should get ID2 element';

        my($id2) = $doc->find('#ID2');
        is $id2->attribute('class'), 'hentry', spec;

    it 'should get .abstract elements';

        my @abstract = $doc->find('.abstract');
        is scalar @abstract, 2, spec;

    it 'should get ABSTRACT1 for 1st abstract';

        is $abstract[0]->child_nodes->[0], 'ABSTRACT1', spec;

    it 'should get ABSTRACT2 for 2nd abstract';

        is $abstract[1]->child_nodes->[0], 'ABSTRACT2', spec;

    it 'should get ID1 h2 a';

        my @id1h2a = $doc->find('#ID1 h2 a');
        is scalar @id1h2a, 1, spec;

    it 'should get TITLE1 here';

        is $id1h2a[0]->child_nodes->[0], 'TITLE1', spec;

    it 'should get rel=bookmark';

        my @bookmark = $doc->find('[rel="bookmark"]');
        is scalar @bookmark, 2, spec;

    it 'should be permalink1 at 1st bookmark';

        is $bookmark[0]->attribute('href'), 'permalink1', spec;

    it 'should be permalink2 at 2nd bookmark';

        is $bookmark[1]->attribute('href'), 'permalink2', spec;

    it 'should get class=hentry';

        my @hentry1 = $doc->find('[class="hentry"]');
        is scalar @hentry1, 1, spec;

    it 'should be ID2 at 1st hentry';

        is $hentry1[0]->attribute('id'), 'ID2', spec;

    it 'should get class~=hentry';

        my @hentry2 = $doc->find('[class~="hentry"]');
        is scalar @hentry2, 2, spec;

    it 'should be ID1 at 1st hentry';

        is $hentry2[0]->attribute('id'), 'ID1', spec;

    it 'should be ID2 at 2nd hentry';

        is $hentry2[1]->attribute('id'), 'ID2', spec;

    it 'should not get class~=entry';

        my @hentry3 = $doc->find('[class~="entry"]');
        is scalar @hentry3, 0, spec;

    it 'should get class^=hent';
        my @hentry4 = $doc->find('[class^="hent"]');
        is scalar @hentry4, 2, spec;

    it 'should be ID1 at 1st hentry';

        is $hentry4[0]->attribute('id'), 'ID1', spec;

    it 'should be ID2 at 2nd hentry';

        is $hentry4[1]->attribute('id'), 'ID2', spec;

    it 'should get class$=pic';
        my @hentry5 = $doc->find('[class$="pic"]');
        is scalar @hentry5, 1, spec;

    it 'should be ID1 at 1st hentry';

        is $hentry5[0]->attribute('id'), 'ID1', spec;

    it 'should get class*=ent';
        my @hentry6 = $doc->find('[class*="ent"]');
        is scalar @hentry6, 4, spec;

    it 'should be ID1 at 1st hentry';

        is $hentry6[0]->attribute('id'), 'ID1', spec;

    it 'should be CONTENT1 at 2nd hentry';

        is $hentry6[1]->child_nodes->[0], 'CONTENT1', spec;

    it 'should be ID2 at 3rd hentry';

        is $hentry6[2]->attribute('id'), 'ID2', spec;

    it 'should be CONTENT2 at 4th hentry';

        is $hentry6[3]->child_nodes->[0], 'CONTENT2', spec;

    it 'should get class|=body';
        my @body1 = $doc->find('[class|="body"]');
        is scalar @body1, 2, spec;

    it 'should be CONTENT1 at 1st hentry';

        is $body1[0]->child_nodes->[0], 'CONTENT1', spec;

    it 'should be CONTENT2 at 2nd hentry';

        is $body1[1]->child_nodes->[0], 'CONTENT2', spec;
}

