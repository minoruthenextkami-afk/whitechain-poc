// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

/**
 * @title FalseReturnERC20
 * @notice Standard-looking ERC-20 whose transfer/transferFrom return false on failure
 *         instead of reverting, matching the behaviour of widely used production tokens.
 */
contract FalseReturnERC20 {
    string public name = "False Return Token";
    string public symbol = "FRT";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Mirrors the production blacklist pattern: the transfer returns false.
    mapping(address => bool) public isBlacklisted;

    function blacklist(address account) external {
        isBlacklisted[account] = true;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (isBlacklisted[msg.sender] || isBlacklisted[to] || balanceOf[msg.sender] < amount) {
            return false;
        }
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (balanceOf[from] < amount || allowance[from][msg.sender] < amount) {
            return false;
        }
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
