require 'spec_helper'
require 'flapjack/data/redis_record'

describe Flapjack::Data::RedisRecord, :redis => true do

  class Flapjack::Data::RedisRecord::ExampleChild
    include Flapjack::Data::RedisRecord
    define_attributes :name => :string
    validates :name, :presence => true
  end

  class Flapjack::Data::RedisRecord::Example
    include Flapjack::Data::RedisRecord

    define_attributes :name   => :string,
                      :email  => :string,
                      :active => :boolean

    validates :name, :presence => true

    index_by :active

    has_many :fdrr_children, :class => Flapjack::Data::RedisRecord::ExampleChild
  end

  let(:redis) { Flapjack.redis }

  def create_example
    redis.hmset('flapjack/data/redis_record/example:8:attrs',
      {'name' => 'John Jones', 'email' => 'jjones@example.com', 'active' => 'true'}.flatten)
    redis.sadd('flapjack/data/redis_record/example::by_active:true', '8')
    redis.sadd('flapjack/data/redis_record/example::ids', '8')
  end

  def create_child
    redis.sadd('flapjack/data/redis_record/example:8:fdrr_child_ids', '3')

    redis.sadd('flapjack/data/redis_record/example_child::ids', '3')
    redis.hmset('flapjack/data/redis_record/example_child:3:attrs',
                {'name' => 'Abel Tasman'}.flatten)
  end

  it "is invalid without a name" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => '1', :email => 'jsmith@example.com')
    example.should_not be_valid

    errs = example.errors
    errs.should_not be_nil
    errs[:name].should == ["can't be blank"]
  end

  it "adds a record's attributes to redis" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => '1', :name => 'John Smith',
      :email => 'jsmith@example.com', :active => true)
    example.should be_valid
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:1:attrs',
                               'flapjack/data/redis_record/example::by_active:true']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['1']
    redis.hgetall('flapjack/data/redis_record/example:1:attrs').should ==
      {'name' => 'John Smith', 'email' => 'jsmith@example.com', 'active' => 'true'}
    redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
      ['1']
  end

  it "finds a record by id in redis" do
    create_example

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "finds records by an indexed value in redis" do
    create_example

    examples = Flapjack::Data::RedisRecord::Example.find_by(:active, true)
    examples.should_not be_nil
    examples.should be_an(Array)
    examples.should have(1).example
    example = examples.first
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "updates a record's attributes in redis" do
    create_example

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.name = 'Jane Janes'
    example.email = 'jjanes@example.com'
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example::by_active:true']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
    redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
      {'name' => 'Jane Janes', 'email' => 'jjanes@example.com', 'active' => 'true'}
    redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
      ['8']
  end

  it "deletes a record's attributes from redis" do
    create_example
    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example::by_active:true']

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.destroy

    redis.keys('*').should == []
  end

  it "sets a parent/child has_many relationship between two records in redis" do
    create_example

    child = Flapjack::Data::RedisRecord::ExampleChild.new(:id => '3', :name => 'Abel Tasman')
    child.save.should be_true

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.fdrr_children << child

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example::by_active:true',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example:8:fdrr_child_ids',
                               'flapjack/data/redis_record/example_child::ids',
                               'flapjack/data/redis_record/example_child:3:attrs']

    redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
    redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
      ['8']
    redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
      {'name' => 'John Jones', 'email' => 'jjones@example.com', 'active' => 'true'}
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == ['3']

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
    redis.hgetall('flapjack/data/redis_record/example_child:3:attrs').should ==
      {'name' => 'Abel Tasman'}
  end

  it "loads a child from a parent's has_many relationship" do
    create_example
    create_child

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    children = example.fdrr_children.all

    children.should be_an(Array)
    children.should have(1).child
    child = children.first
    child.should be_a(Flapjack::Data::RedisRecord::ExampleChild)
    child.name.should == 'Abel Tasman'
  end

  it "removes a parent/child has_many relationship between two records in redis" do
    create_example
    create_child

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    child = Flapjack::Data::RedisRecord::ExampleChild.find_by_id('3')

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == ['3']

    example.fdrr_children.delete(child)

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']    # child not deleted
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == [] # but association is
  end

  # it "sets a parent/child has_one relationship between two records in redis"

  # it "removes a parent/child has_one relationship between two records in redis"

  it "resets changed state on refresh" do
    create_example
    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

    example.name = "King Henry VIII"
    example.changed.should include('name')
    example.changes.should == {'name' => ['John Jones', 'King Henry VIII']}

    example.refresh
    example.changed.should be_empty
    example.changes.should be_empty
  end

  # TODO validate updates of the different data types for attributes


  # TODO tests for set intersection

  # it "finds entities by tag" do
  #   entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
  #                                         'name'     => 'abc-123',
  #                                         'contacts' => []})

  #   entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
  #                                         'name'     => 'def-456',
  #                                         'contacts' => []})

  #   entity0.add_tags('source:foobar', 'abc')
  #   entity1.add_tags('source:foobar', 'def')

  #   entity0.should_not be_nil
  #   entity0.should be_an(Flapjack::Data::Entity)
  #   entity0.tags.should include("source:foobar")
  #   entity0.tags.should include("abc")
  #   entity0.tags.should_not include("def")
  #   entity1.should_not be_nil
  #   entity1.should be_an(Flapjack::Data::Entity)
  #   entity1.tags.should include("source:foobar")
  #   entity1.tags.should include("def")
  #   entity1.tags.should_not include("abc")

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['abc'])
  #   entities.should be_an(Array)
  #   entities.should have(1).entity
  #   entities.first.should == 'abc-123'

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['donkey'])
  #   entities.should be_an(Array)
  #   entities.should have(0).entities
  # end

  # it "finds entities with several tags" do
  #   entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
  #                                        'name'     => 'abc-123',
  #                                        'contacts' => []})

  #   entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
  #                                        'name'     => 'def-456',
  #                                        'contacts' => []})

  #   entity0.add_tags('source:foobar', 'abc')
  #   entity1.add_tags('source:foobar', 'def')

  #   entity0.should_not be_nil
  #   entity0.should be_an(Flapjack::Data::Entity)
  #   entity0.tags.should include("source:foobar")
  #   entity0.tags.should include("abc")
  #   entity1.should_not be_nil
  #   entity1.should be_an(Flapjack::Data::Entity)
  #   entity1.tags.should include("source:foobar")
  #   entity1.tags.should include("def")

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar'])
  #   entities.should be_an(Array)
  #   entities.should have(2).entity

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar', 'def'])
  #   entities.should be_an(Array)
  #   entities.should have(1).entity
  #   entities.first.should == 'def-456'
  # end


end