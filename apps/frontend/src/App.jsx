import React, { useEffect, useState } from 'react'

function App() {
  const [products, setProducts] = useState([])
  const [status, setStatus] = useState('Checking...')
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch('/api/health')
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(() => setStatus('âœ… Connected'))
      .catch(err => setStatus(`âš ï¸ API Unavailable (${err.message})`))

    fetch('/api/products')
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(data => setProducts(Array.isArray(data) ? data : []))
      .catch(err => {
        setError(err.message)
        setProducts([])
      })
  }, [])

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1>í»’ ECommerce Store</h1>
      <p>API Status: <strong>{status}</strong></p>
      {error && <p style={{ color: 'orange' }}>Products error: {error}</p>}
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
