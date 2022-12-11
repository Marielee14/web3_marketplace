// a contract folder:: this holds our NFT marketplace logic and also the sample NFT contract
// https://blog.chain.link/how-to-build-an-nft-marketplace-with-hardhat-and-solidity/

/**
inputs and outputs=> what data do we need? 
1.List the NFT: display on market place 
2.Update and cancel the listing
3.Buy the NFT(transfer ownership)
4.Get a seller's proceeds */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
//@absolute path name didn't work 
import "../node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotOwner();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();

contract NftMarketplace is ReentrancyGuard {

    struct Listing {
        uint256 price; //listing price for the seller's token  
        address seller; //seller's Ethereum account address
    }
//indexed variable: this modifier indcicates taht the variable will be included in the contract's event logs, which can be used to 
//query the blockchain and track the contract's state 
    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    //TODO got an wnarning, no more than 3 indexed items in event???
    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    mapping(address => mapping(uint256 => Listing)) private s_listings; //mapping of NFT contract addresses to tokenID that themselves point to Listinng data structs..
    mapping(address => uint256) private s_proceeds; // mapping between seller's adderss and the amount they've earned in sales 

    modifier isNotListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    )   {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0 ) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }
/** creates a new contract instance called "nft" that is associated with the contract at the given address (nftAddress). 
This allows the current contrac to interact with the contract at the given address as if it were an instance of the IERC721 */
    modifier isOwner( //checks whether the entity that calls listItem() actually owns that item 
        address nftAddress,
        uint256 tokenId,
        address spender
    )   {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

/** from ERC721.sol
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
*/

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }
   
    function listItem(address nftAddress, uint256 tokenId, uint256 price) external isNotListed(nftAddress, tokenId, msg.sender) isOwner(nftAddress, tokenId, msg.sender) {
        //it's external because it needs to be called by other contracts or by end users accounts (from the frontweb applicationi for example)
        if(price <=0) {
            revert PriceMustBeAboveZero();
            //check that the price is greater than zero wei
        } 
        IERC721 nft = IERC721(nftAddress);
        if(nft.getApproved(tokenId) != address(this))  {
            revert NotApprovedForMarketplace() ;
            //ensure that the token's contract has 'approved' our NFT marketplace to operate the token(to transfer it, etc.)
            //TODO how to check if it's approved? 
        } 
        s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
            //TODO Store the listing details in the smart contract's state(i.e. marketplace application's state). so where?? 
    }


    function cancelListing(address nftAddress, uint256 tokenId) external 
    isOwner(nftAddress, tokenId, msg.sender) isListed(nftAddress, tokenId){

        delete (s_listings[nftAddress][tokenId]);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    
    }

    /** This method is the heart of marketplace. it deals directly with payment. 
    1. externally callable, accepts payments, and protects against re-entrancy
    2. the payment received is not less than the elisting's price
    3. the payment received is added to the seller's proceeds
    4. the listing is deleted after the exchange of value
    5. the token is actually transferred to the buyer
    6. the right event is emitted 
    */
     //TODO still don't understand on push/pull: withdrawProceeds()
    /** it’s important to note that we update the seller’s balance in s_proceeds.  This stores the total ether the seller has received 
    for selling their NFTs. We then call on the listed token’s contract to transfer ownership of the token to the buyer 
    (msg.sender is the buyer calling this method). But we do not send the seller their proceeds. This is because we have a withdrawProceeds method later. 
    This pattern “pulls” rather than “pushes” the proceeds; the principle behind the design is covered in this article. In a nutshell, having the seller 
    actively withdraw the funds is a safer operation than having our marketplace contract push it to them, as pushing it may cause execution failures 
    that our contract cannot control. It is better to delegate the power, choice, and responsibility of 
    transferring sales proceeds to the seller, with our contract solely responsible for storing the sale proceeds’ balance. */
    function buyItem(address nftAddress, uint256 tokenId) external payable isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if(msg.value < listedItem.price) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.price);
        }
        s_proceeds[listedItem.seller] += msg.value; // updated seller's balance 
        delete (s_listings[nftAddress][tokenId]);
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId); //msg.sender is the buyer who is calling this method
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price); 
    }
    /** This method allows updating the price in the listing.
    1. checking that the item is already in the list and caller owns the token, guarding against re-entrancy
    2. checking that the new price is not zero
    3. updating the s_listing state mapping so that the correct lissting data object now refers to the updated price
    4. emitting the eright event 
     */
    function updateListing(address nftAddress, uint256 tokenId, uint256 newPrice) external isListed(nftAddress,tokenId) isOwner (nftAddress, tokenId, msg.sender) nonReentrant{
        if (newPrice == 0)   {
            revert PriceMustBeAboveZero();
        }
        s_listings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }
 
    /** means simply sending the caller of the method whatever their balance in the s_proceeds 
    */
    function withdrawProceeds() external {
        uint256 proceeds = s_proceeds[msg.sender];
        if(proceeds <=0) {
            revert NoProceeds();
        }
        s_proceeds[msg.sender] = 0;
        (bool success,) = payable(msg.sender). call{value: proceeds} ("") ; 
        /** This is how solidity sends value to caller address. 
        value = the amount of ether being sent. ("") = solidity call() function is being called with no arguments
        (bool success, )=> .call() function returns 2 values=> boolean denoting success or not, and the data bytes(which we don't use and hence don't assign to any variable
        https://ethereum.stackexchange.com/questions/96685/how-to-use-address-call-in-solidity */

        require(success, "Transfer failed");
    }
    function getListing(address nftAddress, uint256 tokenId) external view returns(Listing memory){
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }

}