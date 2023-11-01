// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUSDT {
    function transferFrom(address _from, address _to, uint _value) external;
    function allowance(address _owner, address _spender) external returns (uint remaining);
    function balanceOf(address _owner) external view returns (uint256);
}

contract DEXTON is IERC20, Ownable(msg.sender) {

  mapping(address => uint256) public possessionTime;
  mapping(address => uint256) public _frozenBalances;
  mapping(address => uint256) _balances;
  mapping(address => uint256) _rewards;
  mapping(address => uint256) _depositedTime;
  mapping(address => uint8) _months;
  mapping(address => bool) _isDepositor;

  mapping (address => mapping (address => uint256)) _allowances;
  
  address constant TEAM_WALLET = 0x88a6BCc5e06Fb3150a596392afEF3d4e1188471c;
  address public usdtAddress;
  address[] depositors;
  uint256 public startTimestamp;
  uint256 public tokenPriceInUSDT;
  uint256 public maxSupply;
  uint256 _totalSupply;
  uint256 _lockedTokensForSixMonth;
  uint256 _rewardTokens;
  uint256 _tokensForPresale;
  uint8 interestOnDeposit;
  uint8 public decimals;
  string public symbol;
  string public name;

  event DEPOSIT(address sender, uint256 amount);
  event PRESALED(address buyer, uint256 amount);

  constructor() {
    name = "DEXTON";
    symbol = "DEXTON";
    decimals = 18;
    _totalSupply = 1000000000 * 1e18;
    maxSupply = _totalSupply;
    usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    tokenPriceInUSDT = 1000000000000000;
    interestOnDeposit = 10;
    startTimestamp = block.timestamp;
    _tokensForPresale = _totalSupply / 20; 
    _lockedTokensForSixMonth = _totalSupply / 10;
    _rewardTokens = _totalSupply / 10;
    _balances[TEAM_WALLET] = _totalSupply / 2;
    _balances[address(this)] = _rewardTokens;

    emit Transfer(address(0), address(this), _rewardTokens);
    emit Transfer(address(0), TEAM_WALLET, _totalSupply/2);
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address _account) external view returns (uint256) {
    return _balances[_account];
  }

  function allowance(address _owner, address _spender) external view returns (uint256) {
    return _allowances[_owner][_spender];
  }

  function transfer(address _recipient, uint256 _amount) external returns (bool) {
    _transfer(msg.sender, _recipient, _amount);
    return true;
  }

  function approve(address _spender, uint256 _amount) external returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
    require(_allowances[_sender][msg.sender] - _amount > 0, "DEXTON: transfer amount exceeds allowance");

    _transfer(_sender, _recipient, _amount);
    _approve(_sender, msg.sender, _allowances[_sender][msg.sender] - _amount);
    return true;
  }

  function burn(uint256 _amount) public returns (bool) {
    _burn(msg.sender, _amount);
    return true;
  }

  function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
    _approve(msg.sender, _spender, _allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
    _approve(msg.sender, _spender, _allowances[msg.sender][_spender] - _subtractedValue);
    return true;
  }

  function buyTokensByPresale(uint256 _amount) public {
    require(_tokensForPresale - _amount * 1e18 >= 0, "DEXTON: presale finished");
    require(IUSDT(usdtAddress).allowance(msg.sender, address(this)) >= tokenPriceInUSDT * _amount, "DEXTON: User has not given enough allowance"); //Checking Allowance in USDT Contract
    require(IUSDT(usdtAddress).balanceOf(msg.sender) >= tokenPriceInUSDT * _amount, "DEXTON: Insufficient user token balance");

    IUSDT(usdtAddress).transferFrom(msg.sender, TEAM_WALLET, _amount * tokenPriceInUSDT);
    _transfer(TEAM_WALLET, msg.sender, _amount * 1e18);
    _tokensForPresale -= _amount * 1e18;
    possessionTime[msg.sender] = block.timestamp;
    emit PRESALED(msg.sender, _amount);
  }

  function deposit(uint256 _amount) external {
    require(_balances[address(this)] > 0, "DEXTON: cann't deposit");
    require(_balances[msg.sender] >= _amount * 1e18, "DEXTON: insufficient token balance");
    
    update();
    _freezeTokens(msg.sender, _amount * 1e18); 
    if (_isDepositor[msg.sender] == false) {
      _isDepositor[msg.sender] == true;
      depositors.push(msg.sender);
    }
    emit DEPOSIT(msg.sender, _amount);
  }

  function withdraw() external {
    require(_balances[address(this)] < 1e17, "DEXTON: can not unfreeze tokens");
    uint256 depositorsLength = depositors.length;
    for(uint256 i; i < depositorsLength; ++i) {
      _unfreezeTokens(depositors[i], _frozenBalances[depositors[i]]);
    }
  }

  function claim() external {
    require(_isDepositor[msg.sender] == true, "DEXTON: you are not a depositor");
    require(_balances[address(this)] != 0, "DEXTON: cann't claim");
    require(_depositedTime[msg.sender] + 30 days > block.timestamp, "DEXTON: not time for claim");
    require(_months[msg.sender] <= 12, "DEXTON: deposit time was expired");

    update();
    if(_rewards[msg.sender] > 0) {
      _transfer(address(this), msg.sender, _rewards[msg.sender]);
      ++_months[msg.sender];
    }
  }

  function unlockTokens() external onlyOwner {
    require(startTimestamp + 180 days > block.timestamp, "DEXTON: cann't unlock");
    _balances[TEAM_WALLET] += _lockedTokensForSixMonth;
    startTimestamp = block.timestamp;
    emit Transfer(address(0), TEAM_WALLET, _totalSupply / 2);
  }

  function _transfer(address _sender, address _recipient, uint256 _amount) internal {
    require(_balances[_sender] - _frozenBalances[_sender] >= _amount, "DEXTON: insufficient token balance");
    require(_sender != address(0), "DEXTON: transfer from the zero address");
    require(_recipient != address(0), "DEXTON: transfer to the zero address");

    _balances[_sender] = _balances[_sender] - _amount;
    _balances[_recipient] = _balances[_recipient] + _amount;
    emit Transfer(_sender, _recipient, _amount);
  }

  function _burn(address _account, uint256 _amount) internal {
    require(_account != address(0), "DEXTON: burn from the zero address");
    require(_balances[_account] > 0, "DEXTON: transfer amount exceeds allowance");

    _balances[_account] = _balances[_account] - _amount;
    _totalSupply = _totalSupply - _amount;
    emit Transfer(_account, address(0), _amount);
  }

  function _approve(address _owner, address _spender, uint256 _amount) internal {
    require(_owner != address(0), "DEXTON: approve from the zero address");
    require(_spender != address(0), "DEXTON: approve to the zero address");

    _allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  function _freezeTokens(address _user, uint256 _amount) private {
    require(_balances[_user] >= _amount, "DEXTON: user does not have enough tokens to freeze");
        
    _frozenBalances[_user] += _amount;
  }

  function _unfreezeTokens(address _user, uint256 _amount) private {
    require(_frozenBalances[_user] >= _amount, "DEXTON: not enough frozen tokens to unfreeze");
      
    _frozenBalances[_user] -= _amount;
  }

  function update() private {
    uint256 rewardAmount = ((block.timestamp - _depositedTime[msg.sender]) / 1 days) * (_frozenBalances[msg.sender]) / 30 / interestOnDeposit / 12;
    _rewards[msg.sender] += rewardAmount;
    _depositedTime[msg.sender] = block.timestamp;
  }
}