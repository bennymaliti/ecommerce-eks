import React, { useEffect, useState } from 'react'

function App() {
  const [products, setProducts] = useState([])
  const [status, setStatus] = useState('Loading...')

  useEffect(() => {
    fetch('/api/health')
      .then(res => res.json())
      .then(() => setStatus('API Connected'))
      .catch(() => setStatus('API Unavailable'))

    fetch('/api/products')
      .then(res => res.json())
      .then(data => setProducts(data))
      .catch(() => setProducts([]))
  }, [])

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '2rem' }}>
      <h1>í»’ ECommerce Store</h1>
      <p>API Status: <strong>{status}</strong></p>
      <h2>Products</h2>
      {products.length === 0 ? (
        <p>No products available</p>
      ) : (
        <ul>
          {products.map(p => (
            <li key={p.id}>{p.name} â€” Â£{p.price}</li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default App
