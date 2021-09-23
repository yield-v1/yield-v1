// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../base/governance/Controllable.sol";

import "hardhat/console.sol";
import "./ITetuLoans.sol";
import "./TetuLoansLib.sol";

contract TetuLoans is ERC721Holder, Controllable, ReentrancyGuard, ITetuLoans {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;
  using TetuLoansLib for uint256[];

  constructor(address _controller) {
    Controllable.initializeControllable(_controller);
  }

  uint256 constant public MAX_POSITIONS_PER_USER = 10;
  uint256 constant public DENOMINATOR = 10000;
  uint256 constant public PLATFORM_FEE_MAX = 500; // 5%

  uint256 public platformFee = 10; // 1% by default
  mapping(uint256 => Loan) public loans;
  uint256 public loansCounter;
  uint256[] public loansList;
  mapping(address => uint256[]) public loansByCollateral;
  mapping(address => uint256[]) public loansByAcquired;
  mapping(address => uint256[]) public borrowerPositions;
  mapping(address => uint256[]) public lenderPositions;
  /// @dev index type => ID => index
  mapping(IndexType => mapping(uint256 => uint256)) public loanIndexes;

  // ************* USER ACTIONS *************

  // assume approve
  function openPosition(
    address _collateralToken,
    uint256 _collateralAmount,
    uint256 _collateralTokenId,
    address _acquiredToken,
    uint256 _acquiredAmount,
    uint256 _loanDurationBlocks,
    uint256 _loanFee
  ) external onlyAllowedUsers nonReentrant returns (uint256){
    require(borrowerPositions[msg.sender].length <= MAX_POSITIONS_PER_USER, "TL: Too many positions");
    require(_loanFee <= DENOMINATOR * 10, "TL: Loan fee absurdly high");
    require(_loanDurationBlocks != 0 || _loanFee == 0, "TL: Fee for instant deal forbidden");
    require(_loanDurationBlocks != 0 || _acquiredAmount != 0, "TL: aAmount for instant deal required");
    require(_collateralAmount == 0 || _collateralTokenId == 0, "TL: Wrong amounts");
    require(_collateralToken != address(0), "TL: Zero cToken");
    require(_acquiredToken != address(0), "TL: Zero aToken");

    Loan memory loan;
    {
      LoanInfo memory info = LoanInfo(
        _loanDurationBlocks,
        _loanFee,
        block.number,
        block.timestamp
      );

      LoanCollateral memory collateral = LoanCollateral(
        _collateralToken,
        getAssetType(_collateralToken),
        _collateralAmount,
        _collateralTokenId
      );

      LoanAcquired memory acquired = LoanAcquired(
        _acquiredToken,
        _acquiredAmount
      );

      LoanExecution memory execution = LoanExecution(
        address(0),
        0,
        0,
        0
      );

      loan = Loan(
        loansCounter, // id
        msg.sender, // borrower
        info,
        collateral,
        acquired,
        execution
      );
    }

    loansList.push(loan.id);
    loanIndexes[IndexType.LIST][loan.id] = loansList.length - 1;

    loansByCollateral[_collateralToken].push(loan.id);
    loanIndexes[IndexType.BY_COLLATERAL][loan.id] = loansByCollateral[_collateralToken].length - 1;

    loansByAcquired[_acquiredToken].push(loan.id);
    loanIndexes[IndexType.BY_ACQUIRED][loan.id] = loansByAcquired[_acquiredToken].length - 1;

    borrowerPositions[msg.sender].push(loan.id);
    loanIndexes[IndexType.BORROWER_POSITION][loan.id] = borrowerPositions[msg.sender].length - 1;

    loans[loan.id] = loan;
    loansCounter++;

    _transferCollateral(loan.collateral, msg.sender, address(this));
    return loan.id;
  }

  function closePosition(uint256 id) external onlyAllowedUsers nonReentrant {
    Loan memory loan = loans[id];
    require(loan.id == id, "TL: Wrong ID");
    require(loan.borrower == msg.sender, "TL: Only borrower can close a position");
    require(loan.execution.lender == address(0), "TL: Can't close bid position");
    _removeLoanFromIndexes(loan);
    borrowerPositions[loan.borrower].removeIndexed(loanIndexes[IndexType.BORROWER_POSITION], loan.id);

    _transferCollateral(loan.collateral, address(this), loan.borrower);
  }

  // assume approve
  function bid(uint256 id, uint256 amount) external onlyAllowedUsers nonReentrant {
    Loan storage loan = loans[id];
    require(loan.id == id, "TL: Wrong ID");
    require(loan.execution.lender == address(0), "TL: Can't bid executed position");
    if (loan.acquired.acquiredAmount != 0) {
      require(amount == loan.acquired.acquiredAmount, "TL: Wrong bid amount");

      uint256 feeAmount = amount * platformFee / DENOMINATOR;
      _transferFee(loan.acquired.acquiredToken, msg.sender, feeAmount);
      uint256 toSend = amount - feeAmount;
      IERC20(loan.acquired.acquiredToken).safeTransferFrom(msg.sender, loan.borrower, toSend);

      loan.execution.lender = msg.sender;
      loan.execution.loanStartBlock = block.number;
      loan.execution.loanStartTs = block.timestamp;
      _removeLoanFromIndexes(loan);

      lenderPositions[msg.sender].push(loan.id);
      loanIndexes[IndexType.LENDER_POSITION][loan.id] = lenderPositions[msg.sender].length - 1;

      // instant buy
      if (loan.info.loanDurationBlocks == 0) {
        _transferCollateral(loan.collateral, address(this), msg.sender);
        _endPosition(loan);
      }
    } else {
      // todo auction
    }
  }

  function claim(uint256 id) external onlyAllowedUsers nonReentrant {
    Loan storage loan = loans[id];
    require(loan.id == id, "TL: Wrong ID");
    require(loan.execution.lender == msg.sender, "TL: Only lender can claim");
    uint256 loanEnd = loan.execution.loanStartBlock + loan.info.loanDurationBlocks;
    require(loanEnd < block.number, "TL: Too early to claim");

    _endPosition(loan);
    _transferCollateral(loan.collateral, address(this), msg.sender);
  }

  // assume approve
  function redeem(uint256 id) external onlyAllowedUsers nonReentrant {
    Loan storage loan = loans[id];
    require(loan.id == id, "TL: Wrong ID");
    require(loan.borrower == msg.sender, "TL: Only borrower can redeem");
    require(loan.execution.lender != address(0), "TL: Not executed position");

    _endPosition(loan);
    uint256 toSend = toRedeem(id);
    IERC20(loan.acquired.acquiredToken).safeTransferFrom(msg.sender, loan.execution.lender, toSend);
    _transferCollateral(loan.collateral, address(this), msg.sender);
  }

  // ************* INTERNAL FUNCTIONS *************

  function _endPosition(Loan storage _loan) internal {
    require(_loan.execution.loanEndTs == 0, "TL: Position claimed");
    _loan.execution.loanEndTs = block.timestamp;
    borrowerPositions[_loan.borrower].removeIndexed(loanIndexes[IndexType.BORROWER_POSITION], _loan.id);
    if (_loan.execution.lender != address(0)) {
      lenderPositions[_loan.execution.lender].removeIndexed(loanIndexes[IndexType.LENDER_POSITION], _loan.id);
    }

  }

  function _transferCollateral(LoanCollateral memory _collateral, address _sender, address _recipient) internal {
    if (_collateral.collateralType == AssetType.ERC20) {
      console.log("TRANSFER: ERC20 token", _collateral.collateralToken, _collateral.collateralAmount);
      IERC20(_collateral.collateralToken).safeTransferFrom(_sender, _recipient, _collateral.collateralAmount);
    } else if (_collateral.collateralType == AssetType.ERC721) {
      console.log("TRANSFER: ERC721 token", _collateral.collateralToken, _collateral.collateralTokenId);
      IERC721(_collateral.collateralToken).safeTransferFrom(_sender, _recipient, _collateral.collateralTokenId);
    } else {
      revert("TL: Wrong asset type");
    }
  }

  function _transferFee(address token, address from, uint256 amount) internal {
    // todo liquidator
    IERC20(token).safeTransferFrom(from, controller(), amount);
  }

  function _removeLoanFromIndexes(Loan memory _loan) internal {
    loansList.removeIndexed(loanIndexes[IndexType.LIST], _loan.id);
    loansByCollateral[_loan.collateral.collateralToken].removeIndexed(loanIndexes[IndexType.BY_COLLATERAL], _loan.id);
    loansByAcquired[_loan.acquired.acquiredToken].removeIndexed(loanIndexes[IndexType.BY_ACQUIRED], _loan.id);
  }

  // ************* VIEWS **************************

  function toRedeem(uint256 id) public view returns (uint256){
    Loan memory loan = loans[id];
    return loan.acquired.acquiredAmount +
    (loan.acquired.acquiredAmount * loan.info.loanFee / DENOMINATOR);
  }

  function getAssetType(address _token) public view returns (AssetType){
    if (isERC721(_token)) {
      return AssetType.ERC721;
    } else if (isERC20(_token)) {
      return AssetType.ERC20;
    } else {
      revert("TL: Unknown asset");
    }
  }

  //noinspection NoReturn
  function isERC721(address _token) public view returns (bool) {
    //slither-disable-next-line unused-return,variable-scope,uninitialized-local
    try IERC721(_token).supportsInterface{gas : 30000}(type(IERC721).interfaceId) returns (bool result){
      return result;
    } catch {
      return false;
    }
  }

  //noinspection NoReturn
  function isERC20(address _token) public view returns (bool) {
    //slither-disable-next-line unused-return,variable-scope,uninitialized-local
    try IERC20(_token).totalSupply{gas : 30000}() returns (uint256){
      return true;
    } catch {
      return false;
    }
  }

  function loanListSize() external view returns (uint256) {
    return loansList.length;
  }
}
