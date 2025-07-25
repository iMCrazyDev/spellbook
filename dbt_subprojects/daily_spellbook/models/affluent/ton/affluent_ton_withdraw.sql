{{ config(
       schema = 'affluent_ton'
       , alias = 'withdraw'
       , materialized = 'incremental'
       , file_format = 'delta'
       , incremental_strategy = 'merge'
       , incremental_predicates = [incremental_predicate('DBT_INTERNAL_DEST.block_date')]
       , unique_key = ['tx_hash', 'block_date']
       , post_hook='{{ expose_spells(\'["ton"]\',
                                   "project",
                                   "affluent",
                                   \'["pshuvalov", "okhlopkov"]\') }}'
   )
 }}

-- based on reference implementation: https://github.com/factorial-finance/action-notification-parser/blob/main/src/index.ts

WITH affluent_ton_pools AS (
    {{ affluent_ton_pools() }}
),
parsed_boc AS (
    SELECT M.block_date, M.tx_hash, M.trace_id, M.tx_now, M.tx_lt, pool_address, pool_name, M.destination as owner_address, body_boc
    FROM {{ source('ton', 'messages') }} M
    JOIN affluent_ton_pools ON M.source = pool_address
    WHERE M.direction = 'out'
    AND M.block_date >= TIMESTAMP '2025-01-19' -- protocol launch
    {% if is_incremental() %}
        AND {{ incremental_predicate('M.block_date') }}
    {% endif %}
    AND opcode = -1582162293 -- 0xa1b21e8b
), parse_output as (
    -- -888946769: 0xcb03bfaf, op::withdraw
    SELECT {{ ton_from_boc('body_boc', [
    ton_begin_parse(),
    ton_skip_bits(32),
    ton_load_uint(64, 'query_id'),
    ton_load_uint(32, 'action_op'),
    ton_return_if_neq('action_op', 3406020527),
    ton_load_uint(16, 'error_code'),
    ton_return_if_neq('error_code', 0),
    ton_load_address('asset'),
    ton_load_coins('amount'),
    ton_load_coins('share')
    ]) }} as result, * from parsed_boc
)
SELECT block_date, tx_hash, trace_id, tx_now, tx_lt, pool_address, pool_name,
owner_address, result.asset, result.amount, result.share
FROM parse_output
WHERE result.action_op = 3406020527 AND result.error_code = 0
