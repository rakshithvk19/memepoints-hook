# Memecoin points hook
The goal of this project is to explore Uniswap V4 hooks by building a hook that issues points to the user based on what is done on the exchange with the memecoin we have created. 

Let's name the memecoin as RAX and the points as SOUL.

RAX token follows ERC-20 standard from solmate library and SOUL token follows ERC-20 standard from solmate too.

## What are points?
Points are ERC-721 tokens given to the users. Using solmate contracts for ERC-721 tokens.

## Criteria for issuing points
1. Each time an user swaps RAX by trading their ETH on the exchange, the user gets the SOULs based on the number of ETH traded.
2. Each time an user provided liquidity to the ETH-RAX pool we have created, the user gets SOULs based on the number of ETH added. 
3. Referrer and referree functionality.


## What the user do with the points(SOUL) ?
1. Nothing

Note:
We are using a mapping to keep track of the REFERRER and REFERREE.
mapping(referreeAddress => referrerAddress) public referredBy // user => referrer [key => value]
So referree cant be repeated and there can be multiple referrer in the mapping.
 
1. REFERRER is the person who is refering someone. 
   1. REFERRER can refer multiple users(REFERREE). 
   2. REFERRER gets 500 points when they reffer someone for the first time.
   3. From the second time onwards, REFERRER gets 10% of the transaction done by the referree as points.
2. REFERREE is the person who is being referred. Each REFRREE can have only 1 REFERRER. 

## What it does
1. Issuing points each time someone buys our memecoin with ETH.
2. Issuing points each time someone adds liquidity to the pool.
3. Referal mechanism where Alice gets 10% of points when she refers Bob to do (1) and (2).
   

