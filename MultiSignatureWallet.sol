
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MultiSignatureWallet
 * @author Crypto Coders
 * @notice کیف پول چندامضایی برای مدیریت مشترک ETH
 *
 * سناریو:
 * چند مالک می‌توانند تراکنش پیشنهاد دهند و تأیید کنند.
 * تراکنش فقط پس از رسیدن به حدنصاب تأییدها قابل اجراست.
 *
 * مثال:
 * 3 مالک و حدنصاب 2 یعنی کیف پول 2-of-3.
 */
contract MultiSignatureWallet {

    // --------------------------------------------------
    // 1. اطلاعات تراکنش
    // --------------------------------------------------

    struct Transaction {
        // آدرس مقصد دریافت‌کننده ETH یا قرارداد مقصد
        address to;

        // مقدار ETH ارسالی برحسب wei
        uint256 value;

        // داده فراخوانی؛ برای انتقال ساده ETH معمولاً خالی است
        bytes data;

        // آیا تراکنش قبلاً اجرا شده است؟
        bool executed;

        // تعداد تأییدهای فعلی
        uint256 numConfirmations;
    }

    // --------------------------------------------------
    // 2. متغیرهای اصلی کیف پول
    // --------------------------------------------------

    // فهرست مالکان کیف پول
    address[] public owners;

    // حداقل تعداد تأییدهای لازم برای اجرای تراکنش
    uint256 public immutable requiredApprovals;

    // بررسی اینکه یک آدرس مالک است یا خیر
    mapping(address => bool) public isOwner;

    // فهرست تراکنش‌های پیشنهادی
    Transaction[] public transactions;

    // ثبت تأیید هر مالک برای هر تراکنش
    // transactionId => owner => confirmed
    mapping(uint256 => mapping(address => bool))
        public isConfirmed;

    // --------------------------------------------------
    // 3. رویدادها
    // --------------------------------------------------

    // هنگام دریافت ETH توسط کیف پول
    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 balance
    );

    // هنگام پیشنهاد تراکنش جدید
    event SubmitTransaction(
        address indexed owner,
        uint256 indexed transactionId,
        address indexed to,
        uint256 value,
        bytes data
    );

    // هنگام تأیید تراکنش توسط مالک
    event ConfirmTransaction(
        address indexed owner,
        uint256 indexed transactionId
    );

    // هنگام لغو تأیید
    event RevokeConfirmation(
        address indexed owner,
        uint256 indexed transactionId
    );

    // هنگام اجرای موفق تراکنش
    event ExecuteTransaction(
        address indexed executor,
        uint256 indexed transactionId
    );

    // --------------------------------------------------
    // 4. خطاهای سفارشی
    // --------------------------------------------------

    error NotOwner();
    error InvalidOwners();
    error InvalidRequiredApprovals();
    error InvalidAddress();
    error TransactionNotFound();
    error AlreadyExecuted();
    error AlreadyConfirmed();
    error NotConfirmed();
    error InsufficientApprovals();
    error ExecutionFailed();

    // --------------------------------------------------
    // 5. Modifier دسترسی مالک
    // --------------------------------------------------

    /**
     * فقط آدرس‌هایی که در فهرست owners هستند
     * می‌توانند توابع محدودشده را اجرا کنند.
     */
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    // --------------------------------------------------
    // 6. Constructor
    // --------------------------------------------------

    /**
     * @param _owners آدرس مالکان کیف پول
     * @param _requiredApprovals تعداد تأییدهای لازم
     *
     * مثال:
     * _owners = [OwnerA, OwnerB, OwnerC]
     * _requiredApprovals = 2
     *
     * نتیجه: کیف پول 2-of-3
     */
    constructor(
        address[] memory _owners,
        uint256 _requiredApprovals
    ) {
        uint256 ownersLength = _owners.length;

        // فهرست مالکان نباید خالی باشد.
        if (ownersLength == 0) {
            revert InvalidOwners();
        }

        // حدنصاب باید حداقل 1 و حداکثر برابر تعداد مالکان باشد.
        if (
            _requiredApprovals == 0 ||
            _requiredApprovals > ownersLength
        ) {
            revert InvalidRequiredApprovals();
        }

        // بررسی و ثبت تک‌ تک مالکان
        for (uint256 i = 0; i < ownersLength; i++) {
            address owner = _owners[i];

            // آدرس صفر مالک معتبر نیست.
            if (owner == address(0)) {
                revert InvalidAddress();
            }

            // آدرس تکراری نباید ثبت شود.
            if (isOwner[owner]) {
                revert InvalidOwners();
            }

            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredApprovals = _requiredApprovals;
    }

    // --------------------------------------------------
    // 7. دریافت ETH
    // --------------------------------------------------

    /**
     * هر آدرسی می‌تواند ETH به کیف پول ارسال کند.
     * این تابع هنگام دریافت ETH بدون calldata اجرا می‌شود.
     */
    receive() external payable {
        emit Deposit(
            msg.sender,
            msg.value,
            address(this).balance
        );
    }

    // --------------------------------------------------
    // 8. پیشنهاد تراکنش
    // --------------------------------------------------

    /**
     * هر مالک می‌تواند یک تراکنش جدید پیشنهاد دهد.
     *
     * @param _to آدرس مقصد
     * @param _value مقدار ETH ارسالی برحسب wei
     * @param _data داده فراخوانی مقصد
     *
     * این تابع تراکنش را اجرا نمی‌کند؛ فقط آن را ثبت می‌کند.
     */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner {
        if (_to == address(0)) {
            revert InvalidAddress();
        }

        uint256 transactionId = transactions.length;

        // ثبت تراکنش جدید با صفر تأیید و وضعیت اجرا‌نشده
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 0
            })
        );

        emit SubmitTransaction(
            msg.sender,
            transactionId,
            _to,
            _value,
            _data
        );
    }

    // --------------------------------------------------
    // 9. تأیید تراکنش
    // --------------------------------------------------

    /**
     * هر مالک می‌تواند تراکنش را یک بار تأیید کند.
     * تأیید به‌تنهایی باعث انتقال ETH نمی‌شود.
     */
    function confirmTransaction(
        uint256 _transactionId
    ) external onlyOwner {
        if (_transactionId >= transactions.length) {
            revert TransactionNotFound();
        }

        Transaction storage txn = transactions[_transactionId];

        if (txn.executed) {
            revert AlreadyExecuted();
        }

        if (isConfirmed[_transactionId][msg.sender]) {
            revert AlreadyConfirmed();
        }

        // ثبت تأیید این مالک
        isConfirmed[_transactionId][msg.sender] = true;

        // افزایش تعداد تأییدها
        txn.numConfirmations += 1;

        emit ConfirmTransaction(
            msg.sender,
            _transactionId
        );
    }

    // --------------------------------------------------
    // 10. لغو تأیید
    // --------------------------------------------------

    /**
     * مالک می‌تواند تأیید خود را قبل از اجرا پس بگیرد.
     * این کار تعداد تأییدهای فعلی را یک واحد کاهش می‌دهد.
     */
    function revokeConfirmation(
        uint256 _transactionId
    ) external onlyOwner {
        if (_transactionId >= transactions.length) {
            revert TransactionNotFound();
        }

        Transaction storage txn = transactions[_transactionId];

        if (txn.executed) {
            revert AlreadyExecuted();
        }

        if (!isConfirmed[_transactionId][msg.sender]) {
            revert NotConfirmed();
        }

        isConfirmed[_transactionId][msg.sender] = false;
        txn.numConfirmations -= 1;

        emit RevokeConfirmation(
            msg.sender,
            _transactionId
        );
    }

    // --------------------------------------------------
    // 11. اجرای تراکنش
    // --------------------------------------------------

    /**
     * پس از رسیدن به حدنصاب، تراکنش قابل اجراست.
     *
     * هر آدرسی می‌تواند اجرای تراکنش آماده را فراخوانی کند؛
     * اما هیچ آدرسی نمی‌تواند حدنصاب تأییدها را دور بزند.
     *
     * وضعیت executed پیش از فراخوانی مقصد ثبت می‌شود.
     * اگر فراخوانی شکست بخورد، revert تمام تغییرات این
     * تراکنش را برمی‌گرداند.
     */
    function executeTransaction(
        uint256 _transactionId
    ) external {
        if (_transactionId >= transactions.length) {
            revert TransactionNotFound();
        }

        Transaction storage txn = transactions[_transactionId];

        if (txn.executed) {
            revert AlreadyExecuted();
        }

        if (txn.numConfirmations < requiredApprovals) {
            revert InsufficientApprovals();
        }

        // اثرات داخلی پیش از تعامل با آدرس خارجی
        txn.executed = true;

        // ارسال ETH و/یا اجرای calldata روی مقصد
        (bool success, ) = txn.to.call{value: txn.value}(
            txn.data
        );

        // در صورت شکست، تراکنش به‌طور کامل revert می‌شود.
        if (!success) {
            revert ExecutionFailed();
        }

        emit ExecuteTransaction(
            msg.sender,
            _transactionId
        );
    }

    // --------------------------------------------------
    // 12. توابع مشاهده اطلاعات
    // --------------------------------------------------

    // تعداد مالکان ثبت‌شده
    function getOwnersCount() external view returns (uint256) {
        return owners.length;
    }

    // تعداد تراکنش‌های پیشنهادی
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    // مشاهده اطلاعات یک تراکنش
    function getTransaction(
        uint256 _transactionId
    )
        external
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        if (_transactionId >= transactions.length) {
            revert TransactionNotFound();
        }

        Transaction storage txn = transactions[_transactionId];

        return (
            txn.to,
            txn.value,
            txn.data,
            txn.executed,
            txn.numConfirmations
        );
    }
}
