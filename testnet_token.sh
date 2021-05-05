#!/usr/bin/env bash

if [ $1 == "help" ]
then
    echo "... name description ticker url icon amount addr-file"
	exit
fi

export ASSET_NAME=$1
export DESCRIPTION=$2
export TICKER=$3
export URL=$4
export ICON=$5
export AMT=$6
export PAYFILE=$7

export CARDANO_NODE_SOCKET_PATH=socket
cardano-node run --topology config/testnet-topology.json --database-path db --config config/testnet-config.json --port 3001 --socket-path "$CARDANO_NODE_SOCKET_PATH" & jobs >& /dev/null

export NETWORK_ID="--testnet-magic 764824073"

if [ $PAYFILE == "" ]
then
	echo "Building payment keys..."
	cardano-cli address key-gen --verification-key-file pay.vkey --signing-key-file pay.skey
	
	echo "Building payment address..."
	cardano-cli address build $NETWORK_ID --payment-verification-key-file pay.vkey --out-file pay.addr
fi

export PAYMENT_ADDR=$(cat pay.addr)
echo "Payment address is: $PAYMENT_ADDR"

read -p "Did you load this Address? (for testnet visit https://developers.cardano.org/en/testnets/cardano/tools/faucet/) [y/n]" -n 1 -r
if [[ $REPLY =~ ^[Nn]$ ]]
then
	echo "Then load up the address and return with the addr-file as last argument"
	exit
fi
echo "UTxOs available:"
cardano-cli query utxo $NETWORK_ID --address $PAYMENT_ADDR

export UTXO=$(cardano-cli query utxo $NETWORK_ID --address $PAYMENT_ADDR | tail -n1 | awk '{print $1;}')
export UTXO_TXIX=$(cardano-cli query utxo $NETWORK_ID --address $PAYMENT_ADDR | tail -n1 | awk '{print $2;}')
echo "UTxO: $UTXO#$UTXO_TXIX"

export AMT=$(cardano-cli query utxo $NETWORK_ID --address $PAYMENT_ADDR --mary-era | tail -n1 | awk '{print $3;}')
echo
echo "Amount to mint: $AMT"

mkdir policy

echo "Generating policy keys..."
cardano-cli address key-gen --verification-key-file policy/policy.vkey --signing-key-file policy/policy.skey

export KEYHASH=$(cardano-cli address key-hash --payment-verification-key-file policy/policy.vkey)

echo "Creating policy script..."
export SCRIPT=policy/policy.script
echo "{" >> $SCRIPT
echo "  \"keyHash\": \"${KEYHASH}\"," >> $SCRIPT
echo "  \"type\": \"sig\"" >> $SCRIPT
echo "}" >> $SCRIPT

cat $SCRIPT

export POLICY_ID=$(cardano-cli transaction policyid --script-file $SCRIPT)

echo "AssetID is: $POLICY_ID.$ASSET_NAME"

echo "Building minting transaction..."
cardano-cli transaction build-raw --mary-era --fee 0 --tx-in $UTXO#$UTXO_TXIX --tx-out $PAYMENT_ADDR+$AMT+"$AMT $POLICY_ID.$ASSET_NAME" --mint="$AMT $POLICY_ID.$ASSET_NAME" --out-file mint.raw

cat mint.raw

echo "Writing protocol parameters..."
cardano-cli query protocol-parameters $NETWORK_ID --out-file protocol.json

cat protocol.json

export FEE=$(cardano-cli transaction calculate-min-fee $NETWORK_ID --tx-body-file mint.raw --tx-in-count 1 --tx-out-count 1 --witness-count 2 --protocol-params-file protocol.json | awk '{print $1;}')
export AMT_OUT=$(expr $AMT - $FEE)

cardano-cli transaction build-raw --mary-era --fee $FEE --tx-in $UTXO#$UTXO_TXIX --tx-out $PAYMENT_ADDR+$AMT_OUT+"$AMT $POLICY_ID.$ASSET_NAME" --mint="$AMT $POLICY_ID.$ASSET_NAME" --out-file mint.raw

cat mint.raw

cardano-cli transaction sign --signing-key-file pay.skey --signing-key-file policy/policy.skey --script-file policy/policy.script --tx-body-file mint.raw --out-file mint.signed

cat mint.signed

echo "Submiting minting transaction..."
cardano-cli transaction submit $NETWORK_ID --tx-file mint.signed

echo "Awaiting token..."
sleep 60
cardano-cli query utxo $NETWORK_ID --address $PAYMENT_ADDR