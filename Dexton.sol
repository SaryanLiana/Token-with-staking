// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IUSDT {
    function transferFrom(address _from, address _to, uint _value) external;
    function allowance(address _owner, address _spender) external returns (uint remaining);
    function balanceOf(address _owner) external view returns (uint256);
}

contract DEXTON is IERC20, Ownable(msg.sender) {
  using SafeMath for uint256;

  mapping (address => uint256) _balances;
  mapping (address => uint256) _rewards;
  mapping(address => uint256) _possessionTime;
  mapping(address => uint256) _depositedTime;
  mapping(address => uint256) _frozenBalances;
  mapping(address => uint8) _months;
  mapping(address => bool) _isDepositor;

  mapping (address => mapping (address => uint256)) _allowances;
  
  address constant TEAM_WALLET = 0x88a6BCc5e06Fb3150a596392afEF3d4e1188471c;
  address public usdtAddress;
  address[] depositors;
  uint256 _totalSupply;
  uint256 _lockedTokensForSixMonth;
  uint256 _rewardTokens;
  uint256 _tokensForPresale;
  uint256 public startTimestamp;
  uint32 tokenPriceInETH;
  uint32 tokenPriceInUSDT;
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
    _totalSupply = 1000000000;
    interestOnDeposit = 10;
    startTimestamp = block.timestamp;
    _tokensForPresale = _totalSupply.div(20); 
    _lockedTokensForSixMonth = _totalSupply.div(10);
    _rewardTokens = _totalSupply.div(10);
    _balances[TEAM_WALLET] = _totalSupply.div(2);
    _balances[address(this)] = _rewardTokens;

    emit Transfer(address(0), address(this), _rewardTokens);
    emit Transfer(address(0), TEAM_WALLET, _totalSupply.div(2));
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
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
    _transfer(_sender, _recipient, _amount);
    _approve(_sender, msg.sender, _allowances[_sender][msg.sender].sub(_amount, "DEXTON: transfer amount exceeds allowance"));
    return true;
  }

  function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
    _approve(msg.sender, _spender, _allowances[msg.sender][_spender].add(_addedValue));
    return true;
  }

  function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
    _approve(msg.sender, _spender, _allowances[msg.sender][_spender].sub(_subtractedValue, "DEXTON: decreased allowance below zero"));
    return true;
  }

  function setUsdtAddress(address _usdtAddress) public onlyOwner {
    usdtAddress = _usdtAddress;
  }

  function buyTokensByPresale(uint256 _amount) payable public {
    require(_tokensForPresale.sub(_amount) >= 0, "DEXTON: presale finished");

    if(msg.value > 0) {
      require(msg.value >= _amount.mul(tokenPriceInETH), "DEXTON: insufficient eth for buying tokens");
      require((msg.sender).balance >= msg.value, "DEXTON: insufficient user eth balance!");

      uint256 amountToReturn = msg.value.sub((_amount.mul(tokenPriceInETH))); 
      uint256 amountToTransfer = msg.value.sub(amountToReturn);

      if(amountToReturn > 0) {
        payable(msg.sender).transfer(amountToReturn);
      }
      payable(TEAM_WALLET).transfer(amountToTransfer);
    }
    else {
      require(IUSDT(usdtAddress).allowance(msg.sender, address(this)) >= tokenPriceInUSDT * _amount, "DEXTON: User has not given enough allowance"); //Checking Allowance in USDT Contract
      require(IUSDT(usdtAddress).balanceOf(msg.sender) >= tokenPriceInUSDT * _amount, "DEXTON: Insufficient user token balance");

      IUSDT(usdtAddress).transferFrom(msg.sender, TEAM_WALLET, _amount * tokenPriceInUSDT);
    }

    _transfer(TEAM_WALLET, msg.sender, _amount);
    _tokensForPresale -= _amount;
    _possessionTime[msg.sender] = block.timestamp;
    emit PRESALED(msg.sender, _amount);

  }

  function deposit(uint256 _amount) external {
    require(_balances[address(this)] > 0, "DEXTON: cann't deposit");
    require(_balances[msg.sender] >= _amount, "DEXTON: insufficient token balance");
    
    update();
    _freezeTokens(msg.sender, _amount); 
    if (_isDepositor[msg.sender] == false) {
      _isDepositor[msg.sender] == true;
      depositors.push(msg.sender);
    }
    emit DEPOSIT(msg.sender, _amount);
  }

  function withdraw() external onlyOwner {
    if(_balances[address(this)] == 0) {
      uint256 depositorsLength = depositors.length;
      for(uint256 i; i < depositorsLength; ++i) {
        _unfreezeTokens(depositors[i], _frozenBalances[depositors[i]]);
      }
    }
  }

  function claim() external {
    require(_isDepositor[msg.sender] == true, " DEXTON: you are not a depositor");
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
    emit Transfer(address(0), TEAM_WALLET, _totalSupply.div(2));
  }

  function _transfer(address _sender, address _recipient, uint256 _amount) internal {
    require(_balances[_sender].sub(_frozenBalances[_sender]) >= _amount, "DEXTON: insufficient token balance");
    require(_sender != address(0), "DEXTON: transfer from the zero address");
    require(_recipient != address(0), "DEXTON: transfer to the zero address");

    _balances[_sender] = _balances[_sender].sub(_amount, "DEXTON: transfer amount exceeds balance");
    _balances[_recipient] = _balances[_recipient].add(_amount);
    emit Transfer(_sender, _recipient, _amount);
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
    uint256 rewardAmount = (block.timestamp.sub(_depositedTime[msg.sender])).div(1 days).mul(_frozenBalances[msg.sender]).div(30 days).div(120);
    _rewards[msg.sender] += rewardAmount;
    _depositedTime[msg.sender] = block.timestamp;
  }
}