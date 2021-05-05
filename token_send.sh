#!/usr/bin/env bash

if [ $1 == "help" ]
then
    echo "... sender receiver amont asset_id"
	exit
fi

export SENDER_ADDR=$1
export RECEIVER_ADDR=$2
export AMT=$3
export $ASSET_ID=$4

export NETWORK_ID="--testnet-magic 764824073"

export UTXO=$(cardano-cli query utxo $NETWORK_ID --address $SENDER_ADDR | tail -n1 | awk '{print $1;}')
export UTXO_TXIX=$(cardano-cli query utxo $NETWORK_ID --address $SENDER_ADDR | tail -n1 | awk '{print $2;}')

export FEE=$(cardano-cli transaction calculate-min-fee $NETWORK_ID --tx-body-file mint.raw --tx-in-count 1 --tx-out-count 1 --witness-count 2 --protocol-params-file protocol.json | awk '{print $1;}')
export AMT_OUT=$(expr $AMT - $FEE)

cardano-cli transaction build-raw --mary-era --fee $FEE --tx-in $UTXO#$UTXO_TXIX --tx-out $RECEIVER_ADDR+$AMT_OUT+"$AMT $ASSET_ID" --mint="$AMT $ASSET_ID" --out-file mint.raw

cat mint.raw

cardano-cli transaction sign --signing-key-file pay.skey --signing-key-file policy/policy.skey --script-file policy/policy.script --tx-body-file mint.raw --out-file mint.signed

cat mint.signed

echo "Submiting minting transaction..."
cardano-cli transaction submit $NETWORK_ID --tx-file mint.signed