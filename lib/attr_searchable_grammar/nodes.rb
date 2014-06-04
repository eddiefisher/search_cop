
require "treetop"

module AttrSearchableGrammar
  module Nodes
    module Base
      def and(node)
        And.new self, node
      end

      def or(node)
        Or.new self, node
      end

      def not
        Not.new self
      end

      def can_flatten?
        false
      end

      def flatten!
        self
      end

      def can_group?
        false
      end

      def group!
        self
      end

      def fulltext?
        false
      end

      def can_optimize?
        can_flatten? || can_group?
      end

      def optimize!
        flatten!.group! while can_optimize?

        finalize!
      end

      def finalize!
        self
      end

      def nodes
        []
      end
    end

    ["Equality", "NotEqual", "GreaterThan", "LessThan", "GreaterThanOrEqual", "LessThanOrEqual", "Matches", "Not"].each do |name|
      const_set name, Class.new(Arel::Nodes.const_get(name))
      const_get(name).send :include, Base
    end

    class MatchesFulltext < Arel::Nodes::Binary
      include Base

      def not
        MatchesFulltextNot.new left, right
      end

      def fulltext?
        true
      end

      def finalize!
        FulltextExpression.new collection, self
      end

      def collection
        left
      end
    end

    class MatchesFulltextNot < MatchesFulltext; end

    class FulltextExpression < Arel::Nodes::Node
      include Base

      attr_reader :collection, :node

      def initialize(collection, node)
        @collection = collection
        @node = node
      end
    end

    class Collection < Arel::Nodes::Node
      include Base

      attr_reader :nodes

      def initialize(*nodes)
        @nodes = nodes.flatten
      end

      def can_flatten?
        nodes.any?(&:can_flatten?) || nodes.any? { |node| node.is_a?(self.class) || node.nodes.size == 1 }
      end

      def flatten!(&block)
        @nodes = nodes.collect(&:flatten!).collect { |node| node.is_a?(self.class) || node.nodes.size == 1 ? node.nodes : node }.flatten

        self
      end

      def can_group?
        nodes.reject(&:fulltext?).any?(&:can_group?) || nodes.select(&:fulltext?).group_by(&:collection).any? { |_, group| group.size > 1 }
      end

      def group!
        @nodes = nodes.reject(&:fulltext?).collect(&:group!) + nodes.select(&:fulltext?).group_by(&:collection).collect { |collection, group| group.size > 1 ? self.class::Fulltext.new(collection, group) : group.first }

        self
      end

      def finalize!
        @nodes = nodes.collect(&:finalize!)

        self
      end
    end

    class FulltextCollection < Collection
      attr_reader :collection

      def initialize(collection, *nodes)
        @collection = collection

        super *nodes
      end

      def fulltext?
        true
      end

      def finalize!
        FulltextExpression.new collection, self
      end
    end

    class And < Collection
      class Fulltext < FulltextCollection; end

      def to_arel
        nodes.inject { |res, cur| Arel::Nodes::And.new [res, cur] }
      end
    end

    class Or < Collection
      class Fulltext < FulltextCollection; end

      def to_arel
        nodes.inject { |res, cur| Arel::Nodes::Or.new res, cur }
      end
    end
  end
end
