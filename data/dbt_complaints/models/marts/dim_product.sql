-- One row per product + sub-product. product_group is stable across CFPB renames.
select row_number() over (order by product, sub_product) as product_key,
       product, sub_product, product_group
from (select distinct product, sub_product, product_group from {{ ref('int_complaints') }})
