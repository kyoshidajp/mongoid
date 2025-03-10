# frozen_string_literal: true

module Mongoid
  module Persistable

    # Defines behavior for persistence operations that create new documents.
    module Creatable
      extend ActiveSupport::Concern

      # Insert a new document into the database. Will return the document
      # itself whether or not the save was successful.
      #
      # @example Insert a document.
      #   document.insert
      #
      # @param [ Hash ] options Options to pass to insert.
      #
      # @return [ Document ] The persisted document.
      def insert(options = {})
        prepare_insert(options) do
          if embedded?
            insert_as_embedded
          else
            insert_as_root
          end
        end
      end

      private

      # Get the atomic insert for embedded documents, either a push or set.
      #
      # @api private
      #
      # @example Get the inserts.
      #   document.inserts
      #
      # @return [ Hash ] The insert ops.
      def atomic_inserts
        { atomic_insert_modifier => { atomic_position => as_attributes }}
      end

      # Insert the embedded document.
      #
      # @api private
      #
      # @example Insert the document as embedded.
      #   document.insert_as_embedded
      #
      # @return [ Document ] The document.
      def insert_as_embedded
        raise Errors::NoParent.new(self.class.name) unless _parent
        if _parent.new_record?
          _parent.insert
        else
          selector = _parent.atomic_selector
          _root.collection.find(selector).update_one(
              positionally(selector, atomic_inserts),
              session: _session)
        end
      end

      # Insert the root document.
      #
      # @api private
      #
      # @example Insert the document as root.
      #   document.insert_as_root
      #
      # @return [ Document ] The document.
      def insert_as_root
        collection.insert_one(as_attributes, session: _session)
      end

      # Post process an insert, which sets the new record attribute to false
      # and flags all the children as persisted.
      #
      # @api private
      #
      # @example Post process the insert.
      #   document.post_process_insert
      #
      # @return [ true ] true.
      def post_process_insert
        self.new_record = false
        flag_descendants_persisted
        true
      end

      # Prepare the insert for execution. Validates and runs callbacks, etc.
      #
      # @api private
      #
      # @example Prepare for insertion.
      #   document.prepare_insert do
      #     collection.insert(as_document)
      #   end
      #
      # @param [ Hash ] options The options.
      #
      # @return [ Document ] The document.
      def prepare_insert(options = {})
        return self if performing_validations?(options) &&
          invalid?(options[:context] || :create)
        run_callbacks(:save, with_children: false) do
          run_callbacks(:create, with_children: false) do
            run_callbacks(:persist_parent, with_children: false) do
              _mongoid_run_child_callbacks(:save) do
                _mongoid_run_child_callbacks(:create) do
                  result = yield(self)
                  if !result.is_a?(Document) || result.errors.empty?
                    post_process_insert
                    post_process_persist(result, options)
                  end
                end
              end
            end
          end
        end
        self
      end

      module ClassMethods

        # Create a new document. This will instantiate a new document and
        # insert it in a single call. Will always return the document
        # whether save passed or not.
        #
        # @example Create a new document.
        #   Person.create(:title => "Mr")
        #
        # @example Create multiple new documents.
        #   Person.create({ title: "Mr" }, { title: "Mrs" })
        #
        # @param [ Hash, Array ] attributes The attributes to create with, or an
        #   Array of multiple attributes for multiple documents.
        #
        # @return [ Document, Array<Document> ] The newly created document(s).
        def create(attributes = nil, &block)
          _creating do
            if attributes.is_a?(::Array)
              attributes.map { |attrs| create(attrs, &block) }
            else
              doc = new(attributes, &block)
              doc.save
              doc
            end
          end
        end

        # Create a new document. This will instantiate a new document and
        # insert it in a single call. Will always return the document
        # whether save passed or not, and if validation fails an error will be
        # raise.
        #
        # @example Create a new document.
        #   Person.create!(:title => "Mr")
        #
        # @example Create multiple new documents.
        #   Person.create!({ title: "Mr" }, { title: "Mrs" })
        #
        # @param [ Hash, Array ] attributes The attributes to create with, or an
        #   Array of multiple attributes for multiple documents.
        #
        # @return [ Document, Array<Document> ] The newly created document(s).
        def create!(attributes = nil, &block)
          _creating do
            if attributes.is_a?(::Array)
              attributes.map { |attrs| create!(attrs, &block) }
            else
              doc = new(attributes, &block)
              doc.fail_due_to_validation! unless doc.insert.errors.empty?
              doc.fail_due_to_callback!(:create!) if doc.new_record?
              doc
            end
          end
        end
      end
    end
  end
end
