module ::Sushi::Core::Controllers

  class RPCController < Controller

    def exec_internal_post(json, context, params) : HTTP::Server::Context
      call = json["call"].to_s

      case call
      when "create_unsigned_transaction"
        return create_unsigned_transaction(json, context, params)
      when "create_transaction"
        return create_transaction(json, context, params)
      when "amount"
        return amount(json, context, params)
      when "blockchain_size"
        return blockchain_size(json, context, params)
      when "blockchain"
        return blockchain(json, context, params)
      when "block"
        return block(json, context, params)
      when "transactions"
        return transactions(json, context, params)
      when "transaction"
        return transaction(json, context, params)
      end

      unpermitted_call(call, context)
    end

    def exec_internal_get(context, params) : HTTP::Server::Context
      unpermitted_method(context)
    end

    def create_transaction(json, context, params)
      transaction = Transaction.from_json(json["transaction"].to_s)

      if transaction.valid?(@blockchain, @blockchain.latest_index, false)
        node.broadcast_transaction(transaction)
        context.response.print transaction.to_json
        return context
      end

      context.response.status_code = 403
      context.response.print "Invalid transaction"
      context
    rescue e : Exception
      context.response.status_code = 403
      context.response.print e.message.not_nil!
      context
    end

    def create_unsigned_transaction(json, context, params)
      action = json["action"].to_s
      senders = Models::Senders.from_json(json["senders"].to_s)
      recipients = Models::Recipients.from_json(json["recipients"].to_s)
      message = json["message"].to_s

      transaction = @blockchain.create_unsigned_transaction(
        action,
        senders,
        recipients,
        message,
      )

      fee = transaction.calculate_fee

      raise "Invalid fee #{fee} for the action #{action}" if fee <= 0.0

      context.response.print transaction.to_json
      context
    end

    def amount(json, context, params)
      address = json["address"].to_s
      unconfirmed = json["unconfirmed"].as_bool

      amount = unconfirmed ?
                 @blockchain.get_amount_unconfirmed(address) :
                 @blockchain.get_amount(address)

      json = { amount: amount, address: address, unconfirmed: unconfirmed }.to_json

      context.response.print json
      context
    end

    def blockchain_size(json, context, params)
      size = @blockchain.chain.size

      json = { size: size }.to_json
      context.response.print json
      context
    end

    def blockchain(json, context, params)
      if json["header"].as_bool
        context.response.print @blockchain.headers.to_json
      else
        context.response.print @blockchain.chain.to_json
      end

      context
    end

    def block(json, context, params)
      block = if index = json["index"]?
                if index.as_i > @blockchain.chain.size - 1
                  raise "Invalid index #{index} (Blockchain size is #{@blockchain.chain.size})"
                end

                @blockchain.chain[index.as_i]
              elsif transaction_id = json["transaction_id"]?
                unless block_index = @blockchain.block_index(transaction_id.to_s)
                  raise "Failed to find a block for the transaction #{transaction_id}"
                end

                @blockchain.chain[block_index]
              else
                raise "Please specify block index or transaction id"
              end

      if json["header"].as_bool
        context.response.print block.to_header.to_json
      else
        context.response.print block.to_json
      end

      context
    end

    def transactions(json, context, params)
      index = json["index"].as_i

      if index > @blockchain.chain.size - 1
        raise "Invalid index #{index} (Blockchain size is #{@blockchain.chain.size})"
      end

      context.response.print @blockchain.chain[index].transactions.to_json
      context
    end

    def transaction(json, context, params)
      transaction_id = json["transaction_id"].to_s

      unless block_index = @blockchain.block_index(transaction_id)
        raise "Failed to find a block for the transaction #{transaction_id}"
      end

      unless transaction = @blockchain.chain[block_index].find_transaction(transaction_id)
        raise "Failed to find a transaction for #{transaction_id}"
      end

      context.response.print transaction.to_json
      context
    end

    def unpermitted_call(call, context) : HTTP::Server::Context
      context.response.status_code = 403
      context.response.print "Unpermitted call: #{call}"
      context
    end

    include Fees
    include Common::Num
  end
end
