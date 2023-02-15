module EnvHelper
  def self.with_env(temp_env, &block)
    original_env = ENV.to_hash
    ENV.merge!(temp_env)
    block.call.tap do
      ENV.clear
      ENV.replace(original_env)
    end
  end

  def self.with_reset(&block)
    with_env({}, &block)
  end
end
