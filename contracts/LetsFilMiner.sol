// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@zondax/filecoin-solidity/contracts/v0.8/cbor/BytesCbor.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/SendAPI.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";

contract LetsFilMiner {
    using BytesCBOR for bytes;

    function spSignWithMiner(uint64 minerId) public {
        //Verify that the node owner is contract address
        CommonTypes.FilAddress memory oldOwner = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(minerId)).owner;
        CommonTypes.FilAddress memory proposed = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(minerId)).proposed;
        bytes memory raw_request = proposed.data.serializeAddress();
        bytes memory result = Actor.callNonSingletonByID(CommonTypes.FilActorId.wrap(minerId), MinerTypes.ChangeOwnerAddressMethodNum, Misc.CBOR_CODEC, raw_request, 0, false);
        if (result.length != 0) {
            revert Actor.InvalidResponseLength();
        }
        CommonTypes.FilAddress memory ownerNew = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(minerId)).owner;
        require(keccak256(oldOwner.data) != keccak256(proposed.data), "LetsFilMiner: set-owner error.");
        require(keccak256(proposed.data) == keccak256(ownerNew.data), "LetsFilMiner: set-owner error.");
    }

    function getOwner(uint64 minerId) public returns (bytes memory) {
         CommonTypes.FilAddress memory nowOwner = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(minerId)).owner;
         return nowOwner.data;
    }

    function backOwner(uint64 minerId, bytes memory oldOwner) public {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(minerId), FilAddresses.fromBytes(oldOwner));
        CommonTypes.FilAddress memory proposed = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(minerId)).proposed;
        require(keccak256(proposed.data) == keccak256(oldOwner), "LetsFilMiner: back-owner error.");
    }

    function changeOwner(uint64 minerId, CommonTypes.FilAddress memory addr) public {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(minerId), addr);
    }

    function changeOwnerById(uint64 minerId, uint64 actorId) public {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(minerId), FilAddresses.fromActorID(actorId));
    }

    //
    function getBalance(uint64 minerId) public {
        CommonTypes.BigInt memory withdrawAmountOne = MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(minerId));
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(minerId), withdrawAmountOne);
    }

    function withdrawAllBalance(uint64 minerId) public {
        CommonTypes.BigInt memory withdrawAmountOne = MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(minerId));
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(minerId), withdrawAmountOne);
    }

    function withdrawMinerBalance(uint64 minerId, uint256 amount) public {
        CommonTypes.BigInt memory withdrawAmount = bigIntsfromUint256(amount);
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(minerId), withdrawAmount);
    }

    function send(uint64 minerId, uint256 amount) public {
        uint256 beforeSend = address(this).balance;
        //CommonTypes.BigInt memory sendAmount = bigIntsfromUint256(amount);
        SendAPI.send(CommonTypes.FilActorId.wrap(minerId), amount);
        require(beforeSend - address(this).balance == amount, "LetsFilMiner: send failure.");
    }

    function bigIntsfromUint256(uint256 amount) public view returns (CommonTypes.BigInt memory) {
        CommonTypes.BigInt memory result = BigInts.fromUint256(amount);
        result.val = removeZeros(result.val);
        return result;
    }

    function removeZeros(bytes memory input) public pure returns (bytes memory) {
        uint i;
        for (i = 0; i < input.length; i++) {
            if (input[i] != 0) {
                break;
            }
        }
        bytes memory output = new bytes(input.length - i);
        for (uint j = 0; j < output.length; j++) {
            output[j] = input[i + j];
        }
        return output;
    }
}
