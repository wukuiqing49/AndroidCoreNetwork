package com.wkq.net.demo

import retrofit2.http.GET
import retrofit2.http.Path

interface DemoApi {
    @GET("posts/{id}")
    suspend fun getPost(@Path("id") id: Int): DemoPost
}
