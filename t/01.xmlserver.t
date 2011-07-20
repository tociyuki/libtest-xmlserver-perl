use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

plan tests => 6;

{
    my($it, $spec);
    sub describe($) { $it = shift }
    sub it($) { $spec = $it . q{ } . shift }
    sub spec() { return $spec }
}

{
    describe 'Test::XmlServer';
    
        my $class = 'Test::XmlServer';
    
    it 'can new';
        
        ok eval{ $class->can('new') }, spec;
    
    it 'should create an instance';
    
        ok eval{
            $class->new(['GET', '/foo', [], {}], [200, [], {}])->isa($class);
        }, spec;
    
    it 'can request';
    
        ok eval{ $class->can('request') }, spec;
    
    it 'can expected';
    
        ok eval{ $class->can('expected') }, spec;
    
    it 'can response';
    
        ok eval{ $class->can('response') }, spec;
    
    it 'can run';
    
        ok eval{ $class->can('run') }, spec;
}

# detail tests in t/04.application.t

