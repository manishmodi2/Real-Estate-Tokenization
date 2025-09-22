class RealEstateTokenization {
    constructor() {
        this.web3 = null;
        this.account = null;
        this.contract = null;
        this.properties = [];
        this.tokens = [];
        
        this.init();
    }

    async init() {
        await this.loadProperties();
        await this.loadTokens();
        this.setupEventListeners();
        this.checkWeb3();
    }

    async checkWeb3() {
        if (typeof window.ethereum !== 'undefined') {
            this.web3 = new Web3(window.ethereum);
            try {
                const accounts = await window.ethereum.request({ 
                    method: 'eth_requestAccounts' 
                });
                this.account = accounts[0];
                this.updateUI();
            } catch (error) {
                console.error('User denied account access');
            }
        } else {
            console.log('Please install MetaMask!');
        }
    }

    setupEventListeners() {
        // Wallet connection
        document.getElementById('connectWallet').addEventListener('click', () => {
            this.openWalletModal();
        });

        // Modal close
        document.querySelector('.close').addEventListener('click', () => {
            this.closeWalletModal();
        });

        // Wallet options
        document.getElementById('metamaskBtn').addEventListener('click', () => {
            this.connectMetaMask();
        });

        document.getElementById('walletConnectBtn').addEventListener('click', () => {
            this.connectWalletConnect();
        });

        // Property exploration
        document.getElementById('exploreProperties').addEventListener('click', () => {
            document.getElementById('properties').scrollIntoView({ behavior: 'smooth' });
        });

        // Tokenization form
        document.getElementById('tokenizeProperty').addEventListener('click', () => {
            this.tokenizeProperty();
        });

        // Marketplace filters
        document.getElementById('filterProperty').addEventListener('change', (e) => {
            this.filterTokens(e.target.value, document.getElementById('filterPrice').value);
        });

        document.getElementById('filterPrice').addEventListener('change', (e) => {
            this.filterTokens(document.getElementById('filterProperty').value, e.target.value);
        });

        // Close modal when clicking outside
        window.addEventListener('click', (e) => {
            const modal = document.getElementById('walletModal');
            if (e.target === modal) {
                this.closeWalletModal();
            }
        });
    }

    openWalletModal() {
        document.getElementById('walletModal').style.display = 'block';
    }

    closeWalletModal() {
        document.getElementById('walletModal').style.display = 'none';
    }

    async connectMetaMask() {
        if (typeof window.ethereum !== 'undefined') {
            try {
                await window.ethereum.request({ method: 'eth_requestAccounts' });
                this.web3 = new Web3(window.ethereum);
                const accounts = await this.web3.eth.getAccounts();
                this.account = accounts[0];
                this.updateUI();
                this.closeWalletModal();
                this.showMessage('Wallet connected successfully!', 'success');
            } catch (error) {
                this.showMessage('Failed to connect wallet', 'error');
            }
        } else {
            this.showMessage('Please install MetaMask!', 'error');
        }
    }

    connectWalletConnect() {
        this.showMessage('WalletConnect integration coming soon!', 'error');
    }

    updateUI() {
        const walletBtn = document.getElementById('connectWallet');
        if (this.account) {
            walletBtn.innerHTML = `<i class="fas fa-wallet"></i> ${this.account.substring(0, 6)}...${this.account.substring(38)}`;
            walletBtn.disabled = false;
        } else {
            walletBtn.innerHTML = '<i class="fas fa-wallet"></i> Connect Wallet';
            walletBtn.disabled = false;
        }
    }

    async loadProperties() {
        // Mock data - replace with actual API calls
        this.properties = [
            {
                id: 1,
                name: 'Luxury Villa in Miami',
                address: '123 Ocean Drive, Miami, FL',
                value: 2500000,
                tokens: 10000,
                pricePerToken: 250,
                image: 'villa.jpg',
                bedrooms: 5,
                bathrooms: 4,
                area: '4500 sq ft'
            },
            {
                id: 2,
                name: 'Downtown Apartment',
                address: '456 Main St, New York, NY',
                value: 1500000,
                tokens: 7500,
                pricePerToken: 200,
                image: 'apartment.jpg',
                bedrooms: 3,
                bathrooms: 2,
                area: '1800 sq ft'
            },
            {
                id: 3,
                name: 'Commercial Building',
                address: '789 Business Ave, Chicago, IL',
                value: 5000000,
                tokens: 20000,
                pricePerToken: 250,
                image: 'commercial.jpg',
                bedrooms: 'N/A',
                bathrooms: 'N/A',
                area: '10000 sq ft'
            }
        ];

        this.renderProperties();
    }

    renderProperties() {
        const grid = document.getElementById('propertiesGrid');
        grid.innerHTML = this.properties.map(property => `
            <div class="property-card">
                <div class="property-image">
                    <i class="fas fa-home fa-3x"></i>
                </div>
                <div class="property-info">
                    <h3>${property.name}</h3>
                    <p class="property-address">${property.address}</p>
                    <div class="property-details">
                        <span><i class="fas fa-bed"></i> ${property.bedrooms}</span>
                        <span><i class="fas fa-bath"></i> ${property.bathrooms}</span>
                        <span><i class="fas fa-ruler-combined"></i> ${property.area}</span>
                    </div>
                    <div class="property-price">$${property.value.toLocaleString()}</div>
                    <div class="token-info">
                        <p>Tokens: ${property.tokens.toLocaleString()}</p>
                        <p>Price per token: $${property.pricePerToken}</p>
                    </div>
                    <button class="btn-primary" onclick="app.buyTokens(${property.id})">
                        Invest Now
                    </button>
                </div>
            </div>
        `).join('');
    }

    async loadTokens() {
        // Mock data - replace with actual API calls
        this.tokens = [
            {
                id: 1,
                propertyId: 1,
                propertyName: 'Luxury Villa in Miami',
                price: 250,
                quantity: 100,
                seller: '0x742...d35',
                forSale: true
            },
            {
                id: 2,
                propertyId: 2,
                propertyName: 'Downtown Apartment',
                price: 200,
                quantity: 50,
                seller: '0x8a3...f91',
                forSale: true
            },
            {
                id: 3,
                propertyId: 1,
                propertyName: 'Luxury Villa in Miami',
                price: 245,
                quantity: 75,
                seller: '0x5b2...c74',
                forSale: true
            }
        ];

        this.renderTokens();
        this.updatePropertyFilter();
    }

    renderTokens() {
        const grid = document.getElementById('tokensGrid');
        grid.innerHTML = this.tokens.map(token => `
            <div class="token-card">
                <div class="token-header">
                    <h4>${token.propertyName}</h4>
                    <span class="token-price">$${token.price}</span>
                </div>
                <p class="token-property">Property ID: ${token.propertyId}</p>
                <p>Quantity: ${token.quantity} tokens</p>
                <p>Seller: ${token.seller}</p>
                <div class="token-actions">
                    <button class="btn-buy" onclick="app.buyToken(${token.id})">
                        Buy Tokens
                    </button>
                    <button class="btn-sell" onclick="app.sellToken(${token.id})">
                        Sell Tokens
                    </button>
                </div>
            </div>
        `).join('');
    }

    updatePropertyFilter() {
        const filter = document.getElementById('filterProperty');
        const uniqueProperties = [...new Set(this.tokens.map(token => token.propertyId))];
        
        uniqueProperties.forEach(propertyId => {
            const property = this.properties.find(p => p.id === propertyId);
            if (property) {
                const option = document.createElement('option');
                option.value = propertyId;
                option.textContent = property.name;
                filter.appendChild(option);
            }
        });
    }

    filterTokens(propertyFilter, priceFilter) {
        let filteredTokens = this.tokens;

        if (propertyFilter) {
            filteredTokens = filteredTokens.filter(token => token.propertyId == propertyFilter);
        }

        if (priceFilter) {
            const [min, max] = priceFilter.split('-').map(Number);
            filteredTokens = filteredTokens.filter(token => token.price >= min && token.price <= max);
        }

        this.renderFilteredTokens(filteredTokens);
    }

    renderFilteredTokens(tokens) {
        const grid = document.getElementById('tokensGrid');
        grid.innerHTML = tokens.map(token => `
            <div class="token-card">
                <div class="token-header">
                    <h4>${token.propertyName}</h4>
                    <span class="token-price">$${token.price}</span>
                </div>
                <p class="token-property">Property ID: ${token.propertyId}</p>
                <p>Quantity: ${token.quantity} tokens</p>
                <p>Seller: ${token.seller}</p>
                <div class="token-actions">
                    <button class="btn-buy" onclick="app.buyToken(${token.id})">
                        Buy Tokens
                    </button>
                    <button class="btn-sell" onclick="app.sellToken(${token.id})">
                        Sell Tokens
                    </button>
                </div>
            </div>
        `).join('');
    }

    async tokenizeProperty() {
        if (!this.account) {
            this.showMessage('Please connect your wallet first', 'error');
            return;
        }

        const address = document.getElementById('propertyAddress').value;
        const value = document.getElementById('propertyValue').value;
        const tokens = document.getElementById('tokensSupply').value;
        const documents = document.getElementById('propertyDocuments').files[0];

        if (!address || !value || !tokens) {
            this.showMessage('Please fill all required fields', 'error');
            return;
        }

        try {
            // Simulate tokenization process
            this.showMessage('Tokenizing property...', 'success');
            
            // Here you would typically interact with your smart contract
            // const result = await this.contract.methods.tokenizeProperty(address, value, tokens).send({ from: this.account });
            
            setTimeout(() => {
                this.showMessage('Property tokenized successfully!', 'success');
                this.resetTokenizationForm();
            }, 2000);

        } catch (error) {
            this.showMessage('Tokenization failed: ' + error.message, 'error');
        }
    }

    resetTokenizationForm() {
        document.getElementById('propertyAddress').value = '';
        document.getElementById('propertyValue').value = '';
        document.getElementById('tokensSupply').value = '';
        document.getElementById('propertyDocuments').value = '';
    }

    async buyTokens(propertyId) {
        if (!this.account) {
            this.showMessage('Please connect your wallet first', 'error');
            return;
        }

        const property = this.properties.find(p => p.id === propertyId);
        if (!property) return;

        try {
            this.showMessage(`Buying tokens for ${property.name}...`, 'success');
            
            // Simulate purchase process
            // const result = await this.contract.methods.buyTokens(propertyId, quantity).send({ from: this.account, value: price });
            
            setTimeout(() => {
                this.showMessage('Tokens purchased successfully!', 'success');
            }, 2000);

        } catch (error) {
            this.showMessage('Purchase failed: ' + error.message, 'error');
        }
    }

    async buyToken(tokenId) {
        if (!this.account) {
            this.showMessage('Please connect your wallet first', 'error');
            return;
        }

        const token = this.tokens.find(t => t.id === tokenId);
        if (!token) return;

        try {
            this.showMessage(`Buying ${token.quantity} tokens...`, 'success');
            
            // Simulate token purchase from marketplace
            // const result = await this.contract.methods.buyToken(tokenId).send({ from: this.account, value: price });
            
            setTimeout(() => {
                this.showMessage('Token purchase completed!', 'success');
            }, 2000);

        } catch (error) {
            this.showMessage('Purchase failed: ' + error.message, 'error');
        }
    }

    async sellToken(tokenId) {
        if (!this.account) {
            this.showMessage('Please connect your wallet first', 'error');
            return;
        }

        // Implement sell token functionality
        this.showMessage('Sell token functionality coming soon!', 'error');
    }

    showMessage(message, type) {
        // Remove existing messages
        const existingMessages = document.querySelectorAll('.message');
        existingMessages.forEach(msg => msg.remove());

        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${type}`;
        messageDiv.textContent = message;
        messageDiv.style.cssText = `
            position: fixed;
            top: 100px;
            right: 20px;
            z-index: 3000;
            padding: 15px 20px;
            border-radius: 5px;
            color: white;
            font-weight: bold;
            max-width: 300px;
            word-wrap: break-word;
        `;

        if (type === 'error') {
            messageDiv.style.background = '#e74c3c';
        } else {
            messageDiv.style.background = '#27ae60';
        }

        document.body.appendChild(messageDiv);

        setTimeout(() => {
            messageDiv.remove();
        }, 5000);
    }
}

// Initialize the application
const app = new RealEstateTokenization();

// Make app globally available for onclick handlers
window.app = app;
