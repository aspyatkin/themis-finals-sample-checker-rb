require 'securerandom'
require 'base64'
require 'digest/sha2'

module Token
  def self.issue_token(name)
    nonce_size = ENV.fetch('THEMIS_FINALS_NONCE_SIZE', '16').to_i

    nonce = ::SecureRandom.random_bytes nonce_size
    secret_key = ::Base64.urlsafe_decode64 ENV["THEMIS_FINALS_#{name}_KEY"]

    hash = ::Digest::SHA256.new
    hash << nonce
    hash << secret_key

    nonce_bytes = nonce.bytes
    digest_bytes = hash.digest.bytes

    token_bytes = nonce_bytes + digest_bytes
    ::Base64.urlsafe_encode64 token_bytes.pack 'c*'
  end

  def self.issue_checker_token
    issue_token 'CHECKER'
  end

  def self.verify_token(name, token)
    return false if token.nil?

    nonce_size = ENV.fetch('THEMIS_FINALS_NONCE_SIZE', '16').to_i

    token_bytes = ::Base64.urlsafe_decode64(token).bytes

    return false if token_bytes.size != 32 + nonce_size

    nonce = token_bytes[0...nonce_size].pack 'c*'
    received_digest_bytes = token_bytes[nonce_size..-1]

    secret_key = ::Base64.urlsafe_decode64 ENV["THEMIS_FINALS_#{name}_KEY"]

    hash = ::Digest::SHA256.new
    hash << nonce
    hash << secret_key

    digest_bytes = hash.digest.bytes

    return digest_bytes == received_digest_bytes
  end

  def self.verify_master_token(token)
    verify_token 'MASTER', token
  end
end
