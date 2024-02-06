// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../LUSDToken.sol";

contract LUSDTokenTester is LUSDToken {
    bytes32 private immutable _PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    constructor(
        address _troveManagerAddress,
        address _stabilityPoolAddress,
        address _borrowerOperationsAddress,
        address _governanceAddress,
        address _guardianAddress
    )
        public
        LUSDToken(
            _troveManagerAddress,
            _stabilityPoolAddress,
            _borrowerOperationsAddress,
            _governanceAddress,
            _guardianAddress
        )
    {}

    function unprotectedMint(address _account, uint256 _amount) external {
        // No check on caller here

        _mint(_account, _amount);
    }

    function unprotectedBurn(address _account, uint _amount) external {
        // No check on caller here

        _burn(_account, _amount);
    }

    function unprotectedSendToPool(
        address _sender,
        address _poolAddress,
        uint256 _amount
    ) external {
        // No check on caller here

        _transfer(_sender, _poolAddress, _amount);
    }

    function unprotectedReturnFromPool(
        address _poolAddress,
        address _receiver,
        uint256 _amount
    ) external {
        // No check on caller here

        _transfer(_poolAddress, _receiver, _amount);
    }

    function callInternalApprove(
        address owner,
        address spender,
        uint256 amount
    ) external returns (bool) {
        _approve(owner, spender, amount);
    }

    function getChainId() external view returns (uint256 chainID) {
        chainID = block.chainid;
    }

    function getDigest(
        address owner,
        address spender,
        uint amount,
        uint nonce,
        uint deadline
    ) external view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    uint16(0x1901),
                    domainSeparator(),
                    keccak256(
                        abi.encode(
                            _PERMIT_TYPEHASH,
                            owner,
                            spender,
                            amount,
                            nonce,
                            deadline
                        )
                    )
                )
            );
    }

    function recoverAddress(
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external pure returns (address) {
        return ecrecover(digest, v, r, s);
    }
}
