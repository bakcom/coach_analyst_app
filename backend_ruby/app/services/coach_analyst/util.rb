require "bigdecimal"

module CoachAnalyst
  # Small numeric/collection helpers that reproduce Python semantics where they
  # differ from Ruby's, so the two backends emit identical payloads.
  module Util
    module_function

    # Python's round() uses banker's rounding (half to even) on the exact binary
    # value of the float. Ruby rounds half away from zero, so reimplement it.
    # With no digits it returns an Integer (as CPython does); with digits, a Float.
    def py_round(value, ndigits = nil)
      return value if value.nil?

      if ndigits.nil?
        BigDecimal(value.to_r, 40).round(0, BigDecimal::ROUND_HALF_EVEN).to_i
      else
        BigDecimal(value.to_r, 40).round(ndigits, BigDecimal::ROUND_HALF_EVEN).to_f
      end
    end

    # Stable sort matching Python's list.sort (Ruby's sort_by is not stable).
    # The block is a comparator; returning 0 preserves the original order.
    def stable_sort(array)
      array.each_with_index.sort do |(a, i), (b, j)|
        result = yield(a, b)
        result.zero? ? (i <=> j) : result
      end.map(&:first)
    end

    # Python's max(dict, key=dict.get): first key wins on ties.
    def max_key(hash)
      best_key = nil
      best_value = nil
      hash.each do |key, value|
        if best_value.nil? || value > best_value
          best_key = key
          best_value = value
        end
      end
      best_key
    end
  end
end
