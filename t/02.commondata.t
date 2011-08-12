use strict;
use warnings;
use Test::Base;
use Test::XmlServer::CommonData;

plan tests => 59;

{
    my($it, $spec);
    sub describe($) { $it = shift }
    sub it($) { $spec = $it . q{ } . shift }
    sub spec() { return $spec }
}

{
    describe 'T::X::CommonData';

        my $class = 'Test::XmlServer::CommonData';

    it 'can new';

        ok eval{ $class->can('new') }, spec;

    it 'can method';

        ok eval{ $class->can('method') }, spec;

    it 'can request_uri';

        ok eval{ $class->can('request_uri') }, spec;

    it 'can code';

        ok eval{ $class->can('code') }, spec;

    it 'can body';

        ok eval{ $class->can('body') }, spec;

    it 'can header';

        ok eval{ $class->can('header') }, spec;

    it 'can param';

        ok eval{ $class->can('param') }, spec;

    it 'can replace';

        ok eval{ $class->can('replace') }, spec;

    it 'can formdata';

        ok eval{ $class->can('formdata') }, spec;

    it 'should create an instance';

        ok eval{ $class->new->isa($class) }, spec;
}

{
    describe 'commondata';

        my $data = Test::XmlServer::CommonData->new;

    it 'should set method POST';

        is $data->method('POST'), 'POST', spec;

    it 'should get method POST';

        is $data->method, 'POST', spec;

    it 'should set method GET';

        is $data->method('GET'), 'GET', spec;

    it 'should get method GET';

        is $data->method, 'GET', spec;

    it 'should replace method';

        is $data->replace('method', 'PUT')->method, 'PUT', spec;

    it 'should set request_uri /foo';

        is $data->request_uri('/foo'), '/foo', spec;

    it 'should get request_uri /foo';

        is $data->request_uri, '/foo', spec;

    it 'should set request_uri /bar';

        is $data->request_uri('/bar'), '/bar', spec;

    it 'should get request_uri /bar';

        is $data->request_uri, '/bar', spec;

    it 'should replace request_uri';

        is $data->replace('request_uri', '/baz')->request_uri, '/baz', spec;

    it 'should set code 200';

        is $data->code(200), 200, spec;

    it 'should get code 200';

        is $data->code, 200, spec;

    it 'should set code 303';

        is $data->code(303), 303, spec;

    it 'should get code 303';

        is $data->code, 303, spec;

    it 'should replace code';

        is $data->replace('code', 400)->code, 400, spec;

    it 'should set body foo';

        is $data->body('foo'), 'foo', spec;

    it 'should get body foo';

        is $data->body, 'foo', spec;

    it 'should set body bar';

        is $data->body('bar'), 'bar', spec;

    it 'should get body bar';

        is $data->body, 'bar', spec;

    it 'should replace body';

        is $data->replace('body', 'baz')->body, 'baz', spec;

    it 'should set header A a0',

        is $data->header('A', 'a0'), 'a0', spec;

    it 'should set header B b0',

        is $data->header('B', 'b0'), 'b0', spec;

    it 'should get header A',

        is $data->header('A'), 'a0', spec;

    it 'should get header B',

        is $data->header('B'), 'b0', spec;

    it 'should set header A a1',

        is $data->header('A', 'a1'), 'a1', spec;

    it 'should set header B b1',

        is $data->header('B', 'b1'), 'b1', spec;

    it 'should get header A',

        is $data->header('A'), 'a1', spec;

    it 'should get header B',

        is $data->header('B'), 'b1', spec;

    it 'should set header Set-Cookie c0';

        is_deeply [$data->header('Set-Cookie', 'c0=0')], ['c0=0'], spec;

    it 'should set header Set-Cookie c1';

        is_deeply [$data->header('Set-Cookie', 'c1=1')], ['c0=0', 'c1=1'], spec;

    it 'should get header Set-Cookie';

        is_deeply [$data->header('Set-Cookie')], ['c0=0', 'c1=1'], spec;

    it 'should get header last Set-Cookie in scalar context';

        is_deeply [scalar $data->header('Set-Cookie')], ['c1=1'], spec;

    it 'should get header names';

        is_deeply [sort $data->header], ['A', 'B', 'Set-Cookie'], spec;

    it 'should replace header';

        $data->replace('header', [
            'Foo' => 'foo', 'Bar' => 'bar', 'Baz' => 'baz',
        ]);
        is_deeply +{
            'name' => [sort $data->header],
            'Foo' => $data->header('Foo'),
            'Bar' => $data->header('Bar'),
            'Baz' => $data->header('Baz'),
        }, +{
            'name' => [sort 'Foo', 'Bar', 'Baz'],
            'Foo' => 'foo',
            'Bar' => 'bar',
            'Baz' => 'baz',
        }, spec;

    it 'should set param A a0';

        is_deeply [$data->param('A', 'a0')], ['a0'], spec;

    it 'should set param A a1';

        is_deeply [$data->param('A', 'a1')], ['a0', 'a1'], spec;

    it 'should get param A';

        is_deeply [$data->param('A')], ['a0', 'a1'], spec;

    it 'should get param last A in scalar context';

        is_deeply [scalar $data->param('A')], ['a1'], spec;

    it 'should set param B b0';

        is_deeply [$data->param('B', 'b0')], ['b0'], spec;

    it 'should get param names';

        is_deeply [sort $data->param], ['A', 'B'], spec;

    it 'should replace param';

        $data->replace('param', [
            'Foo' => 'foo0', 'Bar' => 'bar', 'Baz' => 'baz', 'Foo' => 'foo1',
        ]);
        is_deeply +{
            'name' => [sort $data->param],
            'Foo' => [$data->param('Foo')],
            'Bar' => [$data->param('Bar')],
            'Baz' => [$data->param('Baz')],
        }, +{
            'name' => [sort 'Foo', 'Bar', 'Baz'],
            'Foo' => ['foo0', 'foo1'],
            'Bar' => ['bar'],
            'Baz' => ['baz'],
        }, spec;

    it 'should encode formdata';

        is $data->formdata, 'Bar=bar&Baz=baz&Foo=foo0&Foo=foo1', spec;

    it 'should encode chr(0x00..0x0f) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x00..0x0f);
        is $data->formdata,
            'a=%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F', spec;

    it 'should encode chr(0x10..0x1f) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x10..0x1f);
        is $data->formdata,
            'a=%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F', spec;

    it 'should encode chr(0x20..0x2b) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x20..0x2f);
        is $data->formdata,
            'a=%20%21%22%23%24%25%26%27%28%29%2A%2B,-./', spec;

    it 'should encode chr(0x3a..0x3f) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x30..0x3f);
        is $data->formdata,
            'a=0123456789%3A%3B%3C%3D%3E%3F', spec;

    it 'should encode chr(0x40,0x5b..0x5e) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x40..0x5f);
        is $data->formdata,
            'a=%40ABCDEFGHIJKLMNOPQRSTUVWXYZ%5B%5C%5D%5E_', spec;

    it 'should encode chr(0x60,0x7b..0x7f) in formdata';

        $data->replace('param', 'a' => join q{}, map { chr $_ } 0x60..0x7f);
        is $data->formdata,
            'a=%60abcdefghijklmnopqrstuvwxyz%7B%7C%7D%7E%7F', spec;

    it 'should encode utf8 in formdata';

        $data->replace('param', 'a' => chr(0x3042) . chr(0x3043)); # hiragana a i
        is $data->formdata, 'a=%E3%81%82%E3%81%83', spec;
}

